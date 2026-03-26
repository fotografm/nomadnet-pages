#!/home/user/.venvs/pingtools/bin/python3
# =============================================================================
#  iface-traffic.mu  —  Nomadnet page: Reticulum interface throughput graphs
#  Place in: ~/.nomadnetwork/storage/pages/iface-traffic.mu
#
#  Dependency: ~/.venvs/pingtools/bin/pip install plotille
#
#  How it works:
#    On every page load (c=0) the script:
#      1. Runs rnstatus to read cumulative TX/RX byte counters per interface.
#      2. Compares the new counters against the previous reading (stored on
#         disk) to derive KB/s throughput rates for this interval.
#      3. Appends the rates to per-interface JSON history files.
#      4. Renders a plotille ASCII line graph (TX and RX on the same axes)
#         for any interface that has at least two readings.
#      5. Interfaces with only one reading so far are listed in a "pending"
#         section — reload once more to begin graphing them.
#
#  Graph axes:
#    X — wall-clock time (HH:MM for windows ≤24 h, "Mon HH:MM" for longer).
#        Raw Unix epoch floats are passed to plotille and a unified formatter
#        branches on value magnitude to produce either a timestamp or an
#        integer, keeping X and Y visually distinct.
#    Y — throughput in KB/s, displayed as whole integers.
#
#  Full path to rnstatus is required because Nomadnet does not activate a venv
#  when it executes page scripts, so bare names only resolve via system PATH.
# =============================================================================

import os
import re
import json
import subprocess
import datetime
import time

# =============================================================================
#  USER CONFIGURATION
# =============================================================================

# Plotille canvas dimensions in character cells.
GRAPH_WIDTH  = 60
GRAPH_HEIGHT = 12

# Number of throughput samples to retain per interface in the rolling history.
MAX_POINTS = 60

# Directory where per-interface JSON history files are stored.
DATA_DIR = os.path.expanduser("~/.nomadnetwork/pingdata")

# Full path to rnstatus inside the nomadnet venv.
RNSTATUS_BIN = os.path.expanduser("~/nomadnet-env/bin/rnstatus")

# Interface name prefixes to omit from the page entirely.
SKIP_INTERFACES = ["Shared Instance"]

# =============================================================================
#  END OF USER CONFIGURATION
# =============================================================================

# Single JSON file that holds the rolling history for every interface.
TRAFFIC_FILE = os.path.join(DATA_DIR, "iface_traffic.json")

# Pre-compiled regexes for parsing rnstatus output.
# IFACE_RE — matches the interface header line, e.g.:
#   TCPInterface[MyPeer/1.2.3.4:4242]
IFACE_RE = re.compile(
    r'^\s*(SharedInstance|BackboneInterface|TCPInterface|UDPInterface|'
    r'AutoInterface|AutoInterfacePeer)\[(.+?)\]'
)
# TX_RE — matches the traffic TX line, e.g.:  Traffic : ↑ 1.23 MB
TX_RE = re.compile(r'Traffic\s*:\s*↑\s*([\d.]+)\s*([KMGT]?B)', re.IGNORECASE)
# RX_RE — matches the RX continuation line immediately below TX, e.g.:  ↓ 4.56 KB
RX_RE = re.compile(r'^\s*↓\s*([\d.]+)\s*([KMGT]?B)', re.IGNORECASE)


# ---------------------------------------------------------------------------
#  Unit conversion helpers
# ---------------------------------------------------------------------------

def to_bytes(value, unit):
    """Convert a (value, unit) pair from rnstatus into raw bytes as a float."""
    unit = unit.upper()
    multipliers = {'B': 1, 'KB': 1024, 'MB': 1024**2, 'GB': 1024**3, 'TB': 1024**4}
    return float(value) * multipliers.get(unit, 1)


def fmt_bytes(b):
    """Format a raw byte count as a human-readable string (e.g. '1.23 MB')."""
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if b < 1024:
            return f"{b:.2f} {unit}"
        b /= 1024
    return f"{b:.2f} PB"


# ---------------------------------------------------------------------------
#  rnstatus invocation and parsing
# ---------------------------------------------------------------------------

def run_rnstatus():
    """
    Run rnstatus and return its combined stdout+stderr as a string.
    Returns an empty string if the subprocess fails or times out.
    """
    try:
        result = subprocess.run(
            [RNSTATUS_BIN],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout + result.stderr
    except Exception:
        return ""


def parse_rnstatus(output):
    """
    Parse rnstatus text output into a dict of interface data.

    Returns:
        {
          "InterfaceName": {
              "type":     str,    # e.g. "TCPInterface"
              "status":   str,    # e.g. "Up"
              "tx_bytes": float,  # cumulative bytes sent, or None
              "rx_bytes": float,  # cumulative bytes received, or None
          },
          ...
        }

    rnstatus reports traffic as cumulative totals since the daemon started,
    not as rates — the rate calculation is done separately in update_history().
    """
    interfaces  = {}
    current     = None
    prev_had_tx = False  # flag: next line may be the RX continuation

    for line in output.splitlines():
        iface_match = IFACE_RE.match(line)
        if iface_match:
            iface_type   = iface_match.group(1)
            bracket_name = iface_match.group(2)
            # Use only the part before '/' as the display name
            # (e.g. "MyPeer" from "MyPeer/1.2.3.4:4242").
            iface_name   = bracket_name.split('/')[0].strip()
            current      = iface_name
            prev_had_tx  = False
            interfaces[current] = {
                "type":     iface_type,
                "status":   "Unknown",
                "tx_bytes": None,
                "rx_bytes": None,
            }
            continue

        if current is None:
            continue

        if re.match(r'\s*Status\s*:', line):
            interfaces[current]["status"] = line.split(':', 1)[1].strip()
            continue

        tx_match = TX_RE.search(line)
        if tx_match:
            interfaces[current]["tx_bytes"] = to_bytes(
                tx_match.group(1), tx_match.group(2)
            )
            prev_had_tx = True
            continue

        if prev_had_tx:
            rx_match = RX_RE.match(line)
            if rx_match:
                interfaces[current]["rx_bytes"] = to_bytes(
                    rx_match.group(1), rx_match.group(2)
                )
            # Either consumed or not, clear the flag either way.
            prev_had_tx = False
            continue

        prev_had_tx = False

    return interfaces


# ---------------------------------------------------------------------------
#  Traffic history persistence
# ---------------------------------------------------------------------------

def load_traffic_history():
    """
    Load the rolling throughput history from disk.
    Returns an empty dict if the file is missing or unreadable.
    """
    if os.path.exists(TRAFFIC_FILE):
        try:
            with open(TRAFFIC_FILE) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_traffic_history(history):
    """Persist the throughput history dict to disk."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(TRAFFIC_FILE, 'w') as f:
        json.dump(history, f)


def update_history(history, iface_name, now_ts, tx_bytes, rx_bytes):
    """
    Derive KB/s rates from the difference between the current and previous
    cumulative byte counters, then append to the rolling history.

    Returns (tx_kbps, rx_kbps) — both None on the very first reading for an
    interface because there is no previous sample to diff against.
    """
    if iface_name not in history:
        history[iface_name] = {
            "times":   [],
            "tx_kbps": [],
            "rx_kbps": [],
            "last_tx": None,
            "last_rx": None,
            "last_ts": None,
        }

    h       = history[iface_name]
    tx_kbps = None
    rx_kbps = None

    if h["last_tx"] is not None and h["last_ts"] is not None:
        elapsed = now_ts - h["last_ts"]
        if elapsed > 0:
            tx_delta = tx_bytes - h["last_tx"]
            rx_delta = rx_bytes - h["last_rx"]
            # Clamp to zero to avoid negative spikes when rnsd restarts and
            # resets its cumulative counters.
            tx_kbps = max(0.0, tx_delta / elapsed / 1024)
            rx_kbps = max(0.0, rx_delta / elapsed / 1024)

    # Always update the "last seen" values for the next interval.
    h["last_tx"] = tx_bytes
    h["last_rx"] = rx_bytes
    h["last_ts"] = now_ts

    # Only append a data point when we have a real rate (i.e. not the first
    # reading), then trim the lists to MAX_POINTS.
    if tx_kbps is not None:
        h["times"].append(now_ts)
        h["tx_kbps"].append(tx_kbps)
        h["rx_kbps"].append(rx_kbps)
        for key in ("times", "tx_kbps", "rx_kbps"):
            h[key] = h[key][-MAX_POINTS:]

    return tx_kbps, rx_kbps


# ---------------------------------------------------------------------------
#  Graph rendering
# ---------------------------------------------------------------------------

def _time_label_formatter(val, chars, delta, left=False):
    """
    Plotille axis formatter for Unix epoch X values.

    Converts the epoch float to a local wall-clock string:
      - Window ≤ 24 hours  →  HH:MM          (e.g. "14:37")
      - Window >  24 hours  →  ddd HH:MM     (e.g. "Mon 14:37")

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    dt  = datetime.datetime.fromtimestamp(val)
    fmt = "%H:%M" if delta <= 86400 else "%a %H:%M"
    return '{:>{w}}'.format(dt.strftime(fmt), w=chars)


def _int_label_formatter(val, chars, delta, left=False):
    """
    Plotille axis formatter that renders small floats (KB/s values) as
    whole integers, e.g. "42" instead of "42.00".

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    return '{:>{w}d}'.format(int(round(val)), w=chars)


def _unified_formatter(val, chars, delta, left=False):
    """
    Single formatter registered for the float type on every Figure.

    plotille calls this for both X and Y tick labels.  We distinguish them
    by magnitude: epoch timestamps are ~1.7×10⁹, while KB/s values are small.
    Anything above 1e8 is treated as an epoch and formatted as a time string;
    anything smaller is formatted as a plain integer.
    """
    if val > 1e8:
        return _time_label_formatter(val, chars, delta, left)
    return _int_label_formatter(val, chars, delta, left)


def render_traffic_graph(iface_name, h):
    """
    Build and return a plotille ASCII line graph for a single interface,
    or None if there are fewer than two data points available.

    X axis — raw Unix epoch floats → wall-clock time via _unified_formatter.
    Y axis — KB/s throughput      → whole integers via _unified_formatter.
    Both TX (outbound) and RX (inbound) are plotted as separate lines.
    """
    try:
        import plotille
    except ImportError as e:
        return "plotille import failed: " + str(e)

    times   = h.get("times", [])
    tx_kbps = h.get("tx_kbps", [])
    rx_kbps = h.get("rx_kbps", [])

    if len(times) < 2:
        return None

    x_min = min(times)
    x_max = max(times)
    if x_max == x_min:
        x_max = x_min + 1

    y_max = max(max(tx_kbps), max(rx_kbps)) * 1.15 if (tx_kbps or rx_kbps) else 1

    fig = plotille.Figure()
    fig.width   = GRAPH_WIDTH
    fig.height  = GRAPH_HEIGHT
    fig.x_label = "Time"
    fig.y_label = "KB/s"
    fig.set_x_limits(min_=x_min, max_=x_max)
    fig.set_y_limits(min_=0, max_=y_max if y_max > 0 else 1)

    # Register the unified formatter so both axes get the correct label style.
    fig.register_label_formatter(float, _unified_formatter)

    fig.plot(times, tx_kbps, label="TX KB/s")
    fig.plot(times, rx_kbps, label="RX KB/s")
    return fig.show()


# ---------------------------------------------------------------------------
#  Micron page output
# ---------------------------------------------------------------------------

def micron_page():
    """
    Main entry point.  Collects interface stats, updates histories, then
    emits a Nomadnet micron-formatted page to stdout.

    Processing order:
      1. Run rnstatus and parse interface counters.
      2. Compute throughput rates and persist updated history.
      3. Split interfaces into "graphable" (≥2 samples) and "pending" (1 sample).
      4. Emit the page: graphable interfaces first (with graphs), then pending,
         then any interfaces that reported no traffic counters at all.

    Colour palette:
        `Ffd0  gold   — section headings / interface labels
        `F0f2  green  — dividers / Up status
        `Ff00  red    — Down/Unknown status / errors
        `F0fd  cyan   — numeric data values
        `F888  grey   — secondary / dim labels
    """
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    now_ts  = time.time()

    output     = run_rnstatus()
    interfaces = parse_rnstatus(output)
    history    = load_traffic_history()

    # Derive throughput rates for every interface that has traffic counters,
    # skipping any that are on the SKIP_INTERFACES exclusion list.
    current_rates = {}
    for name, data in interfaces.items():
        if name in SKIP_INTERFACES:
            continue
        if data["tx_bytes"] is None or data["rx_bytes"] is None:
            continue
        tx_kbps, rx_kbps = update_history(
            history, name, now_ts, data["tx_bytes"], data["rx_bytes"]
        )
        current_rates[name] = (tx_kbps, rx_kbps, data)

    save_traffic_history(history)

    # Interfaces with ≥2 history points can be graphed immediately.
    graphable = {
        n: v for n, v in current_rates.items()
        if len(history.get(n, {}).get("times", [])) >= 2
    }
    # Interfaces with only 1 point so far need one more reload.
    pending = {n: v for n, v in current_rates.items() if n not in graphable}

    # --- Page header ---
    # c=0 tells Nomadnet to re-execute the script on every visit, never cache.
    print("#!c=0")
    print("`l`Ffd0Interface Throughput`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`Ffd0Updated:`f  `F0fd{now_str}`f")

    # Bail out early with a useful error if rnstatus produced no output at all.
    if not output:
        print("`Ff00Could not run rnstatus.`f")
        print(f"`F888Expected at: {RNSTATUS_BIN}`f")
        print("`a")
        return

    if not interfaces:
        print("`Ff00No interfaces found in rnstatus output.`f")
        print("`a")
        return

    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # --- Graphable interfaces ---
    for name, (tx_kbps, rx_kbps, data) in graphable.items():
        h = history.get(name, {})

        print()
        print(f"`Ffd0{name}`f  `F888({data['type']})`f")

        status = data.get("status", "")
        if status.lower() == "up":
            print(f"`F888  Status:`f   `F0f2{status}`f")
        else:
            print(f"`F888  Status:`f   `Ff00{status}`f")

        # Cumulative totals from rnstatus (since daemon last started).
        print(f"`F888  Total TX:`f `F0fd{fmt_bytes(data['tx_bytes'])}`f")
        print(f"`F888  Total RX:`f `F0fd{fmt_bytes(data['rx_bytes'])}`f")

        # Current interval rate (None only on the very first reading).
        if tx_kbps is not None:
            print(f"`F888  Now TX:`f   `F0fd{tx_kbps:.3f} KB/s`f")
            print(f"`F888  Now RX:`f   `F0fd{rx_kbps:.3f} KB/s`f")

        # Rolling window statistics.
        tx_hist = h.get("tx_kbps", [])
        rx_hist = h.get("rx_kbps", [])
        if tx_hist:
            print(f"`F888  Avg TX:`f   `F0fd{sum(tx_hist)/len(tx_hist):.3f} KB/s`f")
            print(f"`F888  Avg RX:`f   `F0fd{sum(rx_hist)/len(rx_hist):.3f} KB/s`f")
            print(f"`F888  Peak TX:`f  `F0fd{max(tx_hist):.3f} KB/s`f")
            print(f"`F888  Peak RX:`f  `F0fd{max(rx_hist):.3f} KB/s`f")

        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        graph_str = render_traffic_graph(name, h)
        if graph_str is None:
            print("`F888  Not enough data yet — reload to accumulate readings.`f")
        else:
            # The ``` fence renders the graph in a fixed-width block in Nomadnet.
            print("```")
            print(graph_str)
            print("```")

    # --- Pending interfaces (only one reading so far) ---
    if pending:
        print()
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("`Ffd0First reading — reload to begin graphing`f")
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        for name, (_, _, data) in pending.items():
            status = data.get("status", "")
            colour = "`F0f2" if status.lower() == "up" else "`Ff00"
            tx_str = fmt_bytes(data["tx_bytes"])
            rx_str = fmt_bytes(data["rx_bytes"])
            print(f"`F888  {name}:`f  {colour}{status}`f  `F0fd↑{tx_str}  ↓{rx_str}`f")

    # --- Interfaces with no traffic counters reported ---
    no_traffic = [
        n for n, d in interfaces.items()
        if n not in SKIP_INTERFACES and d["tx_bytes"] is None
    ]
    if no_traffic:
        print()
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("`Ffd0No traffic data reported`f")
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        for name in no_traffic:
            print(f"`F888  {name}`f")

    # --- Page footer ---
    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("`F888Page re-executes on every visit (c=0).`f")
    print(f"`F888Data: {DATA_DIR}`f")
    print("`a")


if __name__ == "__main__":
    micron_page()
