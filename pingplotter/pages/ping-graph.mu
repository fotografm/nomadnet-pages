#!/home/user/.venvs/pingtools/bin/python3
# =============================================================================
#  ping-graph.mu  —  Nomadnet page: ICMP RTT graphs
#  Place in: ~/.nomadnetwork/storage/pages/ping-graph.mu
#
#  Dependencies (install into the venv before first use):
#    ~/.venvs/pingtools/bin/pip install plotille typing_extensions
#
#  How it works:
#    On every page load (c=0) the script:
#      1. Parses ~/.reticulum/config to discover pingable peer hosts.
#      2. Sends one ICMP ping to each host and records the RTT.
#      3. Appends the result to a per-host JSON history file.
#      4. Renders an ASCII line graph (via plotille) for hosts that have
#         responded at least twice, plus summary stats below each graph.
#      5. Hosts that have never responded to ICMP are listed at the bottom
#         without graphs to keep the main view uncluttered.
#
#  Supported interface types (disabled interfaces are always skipped):
#    TCPClientInterface  -> pings the value of  target_host
#    BackboneInterface   -> pings the value of  remote
#    AutoInterface       -> skipped (no fixed remote host)
# =============================================================================

import os
import json
import socket
import subprocess
import re
import time
import datetime

# =============================================================================
#  USER CONFIGURATION
# =============================================================================

# Number of RTT samples to keep in the rolling history per host.
MAX_POINTS = 60

# Dimensions of the plotille ASCII graph in character cells.
GRAPH_WIDTH  = 60
GRAPH_HEIGHT = 15

# Directory where per-host JSON history files and the hostname cache are stored.
DATA_DIR = os.path.expanduser("~/.nomadnetwork/pingdata")

# Path to the Reticulum configuration file used for interface discovery.
RNS_CONFIG = os.path.expanduser("~/.reticulum/config")

# Persistent cache mapping IP addresses to their resolved hostnames,
# avoiding repeated DNS lookups across page reloads.
HOSTNAME_CACHE = os.path.expanduser("~/.nomadnetwork/pingdata/hostname_cache.json")

# =============================================================================
#  END OF USER CONFIGURATION
# =============================================================================


def parse_rns_interfaces():
    """
    Parse the Reticulum config and return a list of (label, host) tuples for
    every enabled interface that exposes a fixed, pingable remote host.

    The config uses nested INI-style sections delimited by [[ name ]].
    Each interface block is split out and its key=value pairs are read to
    determine the interface type, enabled state, and target host field.
    """
    if not os.path.exists(RNS_CONFIG):
        return []

    try:
        with open(RNS_CONFIG) as f:
            content = f.read()
    except Exception:
        return []

    hosts = []

    # Each [[ ... ]] block describes one interface.
    for block in re.split(r'\[\[', content):
        if not block.strip():
            continue

        name_match = re.match(r'^([^\]]+)\]\]', block)
        if not name_match:
            continue
        label = name_match.group(1).strip()

        # Collect key=value pairs, ignoring comment and section header lines.
        fields = {}
        for line in block.splitlines():
            line = line.strip()
            if '=' in line and not line.startswith('[') and not line.startswith('#'):
                key, _, val = line.partition('=')
                fields[key.strip().lower()] = val.strip()

        iface_type = fields.get('type', '').lower()
        enabled    = fields.get('enabled', 'yes').lower()

        # Skip interfaces that are explicitly disabled.
        if enabled in ('no', 'false', '0'):
            continue

        if iface_type == 'tcpclientinterface':
            host = fields.get('target_host')
            if host:
                hosts.append((label, host))
        elif iface_type == 'backboneinterface':
            host = fields.get('remote')
            if host:
                hosts.append((label, host))
        # AutoInterface and any other types are intentionally skipped.

    return hosts


# ---------------------------------------------------------------------------
#  Hostname cache — avoids repeated DNS lookups on every page reload
# ---------------------------------------------------------------------------

def load_hostname_cache():
    """Load the hostname cache dict from disk, returning an empty dict on failure."""
    if os.path.exists(HOSTNAME_CACHE):
        try:
            with open(HOSTNAME_CACHE) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_hostname_cache(cache):
    """Persist the hostname cache dict to disk."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(HOSTNAME_CACHE, 'w') as f:
        json.dump(cache, f, indent=2)


def resolve_hostname(ip, label, cache):
    """
    Return (friendly_name, display_hostname) for a given IP or hostname.

    Resolution is attempted in priority order to minimise latency:
      1. In-memory cache entry — no I/O at all.
      2. /etc/hosts lookup — file read only, no network traffic.
      3. socket.gethostbyaddr() — one network call, then cached permanently.

    For addresses that are already hostnames (not raw IPs), reverse DNS
    resolution is skipped and the hostname is used directly as the display name.
    """
    cache_key = ip

    # Return immediately if this address was already resolved previously.
    if cache_key in cache:
        entry = cache[cache_key]
        if isinstance(entry, dict):
            return entry.get("friendly"), entry.get("hostname", ip)
        else:
            # Legacy cache format — plain string value.
            return None, entry

    friendly = label
    is_ip    = bool(re.match(r'^\d+\.\d+\.\d+\.\d+$', ip))

    # Hostnames don't need reverse DNS; use them verbatim.
    if not is_ip:
        cache[cache_key] = {"friendly": friendly, "hostname": ip}
        save_hostname_cache(cache)
        return friendly, ip

    # Attempt /etc/hosts lookup first (no network round-trip).
    hostname = None
    try:
        with open('/etc/hosts') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[0] == ip:
                    hostname = parts[1]
                    break
    except Exception:
        pass

    # Fall back to a full reverse DNS query if /etc/hosts had no entry.
    if not hostname:
        try:
            hostname = socket.gethostbyaddr(ip)[0]
        except Exception:
            hostname = ip  # Use the raw IP if resolution fails.

    cache[cache_key] = {"friendly": friendly, "hostname": hostname}
    save_hostname_cache(cache)
    return friendly, hostname


# ---------------------------------------------------------------------------
#  ICMP probing
# ---------------------------------------------------------------------------

def probe_host(host):
    """
    Send a single ICMP echo request to *host* and return the average RTT in
    milliseconds as a float, or None if the host is unreachable or the
    subprocess times out.
    """
    try:
        result = subprocess.run(
            ['ping', '-c', '1', '-W', '2', host],
            capture_output=True, text=True, timeout=5
        )
        match = re.search(r'rtt min/avg/max/mdev = [\d.]+/([\d.]+)/', result.stdout)
        if match:
            return float(match.group(1))
        return None
    except Exception:
        return None


# ---------------------------------------------------------------------------
#  Per-host RTT history — stored as JSON on disk
# ---------------------------------------------------------------------------

def load_history(label):
    """
    Load the rolling RTT history for an interface from its JSON file.
    Returns a dict with lists: 'times' (epoch floats), 'rtts' (ms or None),
    and 'timestrings' (human-readable timestamps).
    """
    safe_label = re.sub(r'[^\w\-]', '_', label)
    path = os.path.join(DATA_DIR, safe_label + '.json')
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            pass
    return {"times": [], "rtts": [], "timestrings": []}


def save_history(label, history):
    """
    Persist the RTT history to disk, trimming each list to MAX_POINTS entries
    so files do not grow unbounded over time.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    safe_label = re.sub(r'[^\w\-]', '_', label)
    path = os.path.join(DATA_DIR, safe_label + '.json')

    # Trim all lists to the rolling window size before writing.
    for key in ("times", "rtts", "timestrings"):
        if key in history:
            history[key] = history[key][-MAX_POINTS:]

    with open(path, 'w') as f:
        json.dump(history, f)


# ---------------------------------------------------------------------------
#  Graph rendering
# ---------------------------------------------------------------------------

def _time_label_formatter(val, chars, delta, left=False):
    """
    Custom plotille X-axis formatter that converts a Unix epoch float into a
    wall-clock time string.

    The format adapts to the span of the visible window (delta = x_max - x_min):
      - Window <= 24 hours  ->  HH:MM        (e.g. "14:37")
      - Window >  24 hours  ->  ddd HH:MM    (e.g. "Mon 14:37")

    This lets the label stay meaningful whether the history file contains a
    single hour of pings or several days of data.

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    dt  = datetime.datetime.fromtimestamp(val)
    fmt = "%H:%M" if delta <= 86400 else "%a %H:%M"
    s   = dt.strftime(fmt)
    # Right-align within the character budget plotille allocates for this tick.
    return '{:>{width}}'.format(s, width=chars)


def _int_label_formatter(val, chars, delta, left=False):
    """
    Custom plotille Y-axis formatter that renders RTT values as whole integers
    with no decimal places (e.g. "42" rather than "42.00").

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    return '{:>{width}d}'.format(int(round(val)), width=chars)


def render_graph(label, history):
    """
    Build and return a plotille ASCII line graph string for the given history,
    or None if there are fewer than two valid (non-timeout) data points.

    X axis — real wall-clock time (HH:MM, or day+HH:MM for multi-day windows).
    Y axis — RTT in milliseconds, displayed as whole integers.

    Raw Unix epoch floats are passed directly to plotille so the formatter
    receives the actual timestamp and can derive the correct local time.
    """
    try:
        import plotille
    except ImportError as e:
        return "plotille import failed: " + str(e)

    rtts_raw  = history.get("rtts", [])
    times_raw = history.get("times", [])

    # Drop timeout entries (None) — plotille cannot plot missing values.
    valid_pairs = [(t, r) for t, r in zip(times_raw, rtts_raw) if r is not None]
    if len(valid_pairs) < 2:
        return None

    # Use raw epoch floats for X so the time formatter has the full timestamp.
    xs = [p[0] for p in valid_pairs]
    ys = [p[1] for p in valid_pairs]

    x_min = min(xs)
    x_max = max(xs)
    # Guard against a degenerate window (all samples at the same second).
    if x_max == x_min:
        x_max = x_min + 1

    fig = plotille.Figure()
    fig.width   = GRAPH_WIDTH
    fig.height  = GRAPH_HEIGHT
    fig.x_label = "Time"
    fig.y_label = "RTT (ms)"
    fig.set_x_limits(min_=x_min, max_=x_max)
    fig.set_y_limits(min_=0, max_=max(ys) * 1.15)

    # Register per-axis formatters: time strings on X, plain integers on Y.
    fig.register_label_formatter(float, _time_label_formatter)
    fig.plot(xs, ys, label=label)

    # Swap Y-axis back to integers — register_label_formatter is global for the
    # type, so we patch the rendered string: re-render with integer formatter
    # applied only to Y by using a second Figure for Y ticks is complex; instead
    # we accept HH:MM on both axes for the X pass and fix Y by post-processing
    # the output with a targeted replacement.  Simpler: use two formatters keyed
    # on value magnitude.  The cleanest solution supported by plotille's API is
    # to register a single formatter that inspects the value range itself.
    #
    # We achieve correct axis independence by rendering with the time formatter
    # (which only makes sense for epoch-scale floats ~1.7e9), then registering
    # the integer formatter for the Y axis.  plotille always formats X first,
    # then Y; because all Y values are small RTTs (< ~10000), we detect them
    # inside a unified formatter and branch accordingly.
    fig2 = plotille.Figure()
    fig2.width   = GRAPH_WIDTH
    fig2.height  = GRAPH_HEIGHT
    fig2.x_label = "Time"
    fig2.y_label = "RTT (ms)"
    fig2.set_x_limits(min_=x_min, max_=x_max)
    fig2.set_y_limits(min_=0, max_=max(ys) * 1.15)

    # Unified formatter: epoch-scale values (> 1e8) are timestamps -> HH:MM,
    # small values are RTTs -> integer ms.
    def _unified_formatter(val, chars, delta, left=False):
        if val > 1e8:
            return _time_label_formatter(val, chars, delta, left)
        return _int_label_formatter(val, chars, delta, left)

    fig2.register_label_formatter(float, _unified_formatter)
    fig2.plot(xs, ys, label=label)
    return fig2.show()


# ---------------------------------------------------------------------------
#  Micron page output
# ---------------------------------------------------------------------------

def micron_page():
    """
    Main entry point.  Probes all discovered hosts, updates their histories,
    then emits a Nomadnet micron-formatted page to stdout.

    Colour palette used throughout:
        `Ffd0  gold   — section headings / interface labels
        `F0f2  green  — good RTT / divider lines
        `Ff00  red    — timeouts / high RTT / errors
        `F0fd  cyan   — IP addresses / numeric data values
        `Ffff  white  — hostnames / friendly names
        `F888  grey   — secondary / dim labels
    """
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    hosts          = parse_rns_interfaces()
    hostname_cache = load_hostname_cache()

    # --- Phase 1: probe every host and persist the results ---
    # All probes are done before any output is generated so that the page
    # header timestamp reflects the moment all pings completed.
    results = {}
    for (label, host) in hosts:
        rtt            = probe_host(host)
        history        = load_history(label)
        friendly, rdns = resolve_hostname(host, label, hostname_cache)

        history["times"].append(time.time())
        history["rtts"].append(rtt)
        history["timestrings"].append(now_str)

        save_history(label, history)
        results[label] = (rtt, history, host, friendly, rdns)

    # --- Phase 2: split hosts into those that have ever responded vs. never ---
    responding     = []
    not_responding = []
    for (label, host) in hosts:
        rtt, history, h, friendly, rdns = results[label]
        if any(r is not None for r in history["rtts"]):
            responding.append((label, host))
        else:
            not_responding.append((label, host))

    # --- Phase 3: emit the micron page ---
    # The c=0 directive must be the very first line printed; it tells Nomadnet
    # to re-execute this script on every visit rather than caching the output.
    print("#!c=0")
    print("`l`Ffd0RTT Monitor`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`Ffd0Updated:`f  `F0fd{now_str}`f")

    if not hosts:
        print("`Ff00No pingable interfaces found in reticulum config.`f")

    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # --- Full graph entries for hosts that have responded at least once ---
    for (label, host) in responding:
        rtt, history, host, friendly, rdns = results[label]
        is_ip = bool(re.match(r'^\d+\.\d+\.\d+\.\d+$', host))

        print()
        print(f"`Ffd0{label}`f")

        # Show reverse DNS and/or raw IP depending on what we know.
        if is_ip:
            if rdns and rdns != host:
                print(f"`F888  Host:`f     `Ffff{rdns}`f")
            print(f"`F888  IP:`f       `F0fd{host}`f")
        else:
            print(f"`F888  Host:`f     `Ffff{host}`f")

        print()

        # Colour-code the current RTT: green < 10 ms, gold < 100 ms, red >= 100 ms.
        if rtt is None:
            print("`Ff00  Now:       TIMEOUT`f")
        elif rtt < 10:
            print(f"`F888  Now:`f      `F0f2{rtt:.3f} ms`f")
        elif rtt < 100:
            print(f"`F888  Now:`f      `Ffd0{rtt:.3f} ms`f")
        else:
            print(f"`F888  Now:`f      `Ff00{rtt:.3f} ms`f")

        # Compute summary statistics from the rolling window, excluding timeouts.
        rtts_valid = [r for r in history["rtts"] if r is not None]
        total = len(history["rtts"])
        lost  = total - len(rtts_valid)
        avg   = sum(rtts_valid) / len(rtts_valid)
        mn    = min(rtts_valid)
        mx    = max(rtts_valid)

        print(f"`F888  Min:`f       `F0fd{mn:.3f} ms`f")
        print(f"`F888  Avg:`f       `F0fd{avg:.3f} ms`f")
        print(f"`F888  Max:`f       `F0fd{mx:.3f} ms`f")

        if lost > 0:
            pct = 100 * lost // total
            print(f"`F888  Loss:`f      `Ff00{lost}/{total} ({pct}%)`f")
        else:
            print(f"`F888  Loss:`f      `F0f20/{total} (0%)`f")

        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        graph_str = render_graph(label, history)
        if graph_str is None:
            print("`F888  Not enough data yet — reload to accumulate readings.`f")
        else:
            # The ``` fence renders the graph in a fixed-width block in Nomadnet.
            print("```")
            print(graph_str)
            print("```")

        # Show the timestamps of the most recent timeouts (up to 3) if any occurred.
        timeouts = [
            (i, ts)
            for i, (ts, r) in enumerate(
                zip(history.get("timestrings", []), history["rtts"])
            )
            if r is None
        ]
        if timeouts:
            print()
            print(f"`Ff00  Timeouts in window: {len(timeouts)}`f")
            for _, ts in timeouts[-3:]:
                print(f"`F888  {ts}`f")

    # --- Brief summary section for hosts that have never responded to ICMP ---
    if not_responding:
        print()
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("`Ffd0No ICMP response — not graphed`f")
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        for (label, host) in not_responding:
            _, _, host, friendly, rdns = results[label]
            is_ip = bool(re.match(r'^\d+\.\d+\.\d+\.\d+$', host))

            if is_ip and rdns and rdns != host:
                display = f"`Ffff{rdns}`f  `F0fd({host})`f"
            elif is_ip:
                display = f"`F0fd{host}`f"
            else:
                display = f"`Ffff{host}`f"

            print(f"`F888  {label}:`f  {display}")

    # --- Page footer ---
    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("`F888Page re-executes on every visit (c=0).`f")
    print(f"`F888Config: {RNS_CONFIG}`f")
    print(f"`F888Data:   {DATA_DIR}`f")
    print("`a")


if __name__ == "__main__":
    micron_page()
