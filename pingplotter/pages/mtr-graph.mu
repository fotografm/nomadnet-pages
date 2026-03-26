#!/home/user/.venvs/pingtools/bin/python3
# =============================================================================
#  mtr-graph.mu  —  Nomadnet page: MTR per-hop latency graphs
#  Place in: ~/.nomadnetwork/storage/pages/mtr-graph.mu
#  Dependency: ~/.venvs/pingtools/bin/pip install plotille
#  System dep: sudo apt install mtr-tiny
#
#  Runs mtr against each host from ~/.reticulum/config, stores per-hop
#  RTT history, and plots each hop as a separate line on one graph.
#  Only hosts that responded to mtr in the past are graphed.
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

GRAPH_WIDTH    = 60
GRAPH_HEIGHT   = 15
MAX_POINTS     = 30    # mtr is slower than ping — keep window smaller
DATA_DIR       = os.path.expanduser("~/.nomadnetwork/pingdata")
RNS_CONFIG     = os.path.expanduser("~/.reticulum/config")

# mtr cycles per run — more = more accurate but slower page load
MTR_CYCLES     = 3

# mtr timeout per host in seconds
MTR_TIMEOUT    = 20

# Maximum number of hosts to run mtr against per page load.
# mtr is slow — cap this to keep page load time reasonable.
# Hosts are taken in config file order.
MAX_HOSTS      = 4

# =============================================================================
#  END OF USER CONFIGURATION
# =============================================================================

MTR_DATA_DIR = os.path.join(DATA_DIR, "mtr")


def parse_rns_interfaces():
    """
    Parse ~/.reticulum/config, return list of (label, host) for enabled
    TCPClientInterface and BackboneInterface entries.
    """
    if not os.path.exists(RNS_CONFIG):
        return []
    try:
        with open(RNS_CONFIG) as f:
            content = f.read()
    except Exception:
        return []

    hosts = []
    for block in re.split(r'\[\[', content):
        if not block.strip():
            continue
        name_match = re.match(r'^([^\]]+)\]\]', block)
        if not name_match:
            continue
        label = name_match.group(1).strip()

        fields = {}
        for line in block.splitlines():
            line = line.strip()
            if '=' in line and not line.startswith('[') and not line.startswith('#'):
                key, _, val = line.partition('=')
                fields[key.strip().lower()] = val.strip()

        iface_type = fields.get('type', '').lower()
        enabled    = fields.get('enabled', 'yes').lower()
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

    return hosts[:MAX_HOSTS]


def run_mtr(host):
    """
    Run mtr in report mode with JSON output.
    Returns parsed dict or None on failure.

    JSON output structure:
    {
      "report": {
        "mtr": { "dst": "...", ... },
        "hubs": [
          { "count": 1, "host": "...", "Avg": 1.23, "Loss%": 0.0, ... },
          ...
        ]
      }
    }
    """
    try:
        result = subprocess.run(
            ['mtr', '--report', f'--report-cycles={MTR_CYCLES}',
             '--json', '--no-dns', host],
            capture_output=True, text=True, timeout=MTR_TIMEOUT
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
        return None


def extract_hops(mtr_data):
    """
    Extract hop list from mtr JSON output.
    Returns list of {"hop": int, "host": str, "avg_ms": float, "loss_pct": float}
    Hops with host "???" (no response) are included with avg_ms = None.
    """
    if not mtr_data:
        return []
    try:
        hubs = mtr_data["report"]["hubs"]
    except (KeyError, TypeError):
        return []

    hops = []
    for hub in hubs:
        hop_host = hub.get("host", "???")
        avg      = hub.get("Avg")
        loss     = hub.get("Loss%", 100.0)
        hops.append({
            "hop":      hub.get("count", 0),
            "host":     hop_host,
            "avg_ms":   float(avg) if avg is not None else None,
            "loss_pct": float(loss)
        })
    return hops


def load_mtr_history(label):
    os.makedirs(MTR_DATA_DIR, exist_ok=True)
    safe = re.sub(r'[^\w\-]', '_', label)
    path = os.path.join(MTR_DATA_DIR, safe + '.json')
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            pass
    # Structure: { "hop_N_host": { "times": [], "rtts": [], "losses": [] } }
    return {}


def save_mtr_history(label, history):
    os.makedirs(MTR_DATA_DIR, exist_ok=True)
    safe = re.sub(r'[^\w\-]', '_', label)
    path = os.path.join(MTR_DATA_DIR, safe + '.json')
    # Trim all series
    for hop_key in history:
        for field in ("times", "rtts", "losses"):
            if field in history[hop_key]:
                history[hop_key][field] = history[hop_key][field][-MAX_POINTS:]
    with open(path, 'w') as f:
        json.dump(history, f)


def update_mtr_history(history, hops, now_ts):
    """Append this run's hop data into history."""
    for hop in hops:
        key = f"hop_{hop['hop']:02d}"
        if key not in history:
            history[key] = {
                "hop":    hop["hop"],
                "host":   hop["host"],
                "times":  [],
                "rtts":   [],
                "losses": []
            }
        # Update host name in case it changed
        if hop["host"] != "???":
            history[key]["host"] = hop["host"]
        history[key]["times"].append(now_ts)
        history[key]["rtts"].append(hop["avg_ms"])
        history[key]["losses"].append(hop["loss_pct"])


def render_mtr_graph(label, history):
    """
    Plot one line per hop that has at least one valid RTT reading.
    Returns graph string or None.
    """
    try:
        import plotille
    except ImportError as e:
        return "plotille import failed: " + str(e)

    # Collect hops with valid data, sorted by hop number
    hop_keys = sorted(
        [k for k in history if history[k].get("rtts")],
        key=lambda k: history[k]["hop"]
    )

    if not hop_keys:
        return None

    # Need at least 2 time points on any hop to draw
    any_graphable = any(
        len([r for r in history[k]["rtts"] if r is not None]) >= 2
        for k in hop_keys
    )
    if not any_graphable:
        return None

    # Build common x-axis from all timestamps across all hops
    all_times = []
    for k in hop_keys:
        all_times.extend(history[k]["times"])
    if not all_times:
        return None
    x0 = min(all_times)

    # Global y max across all hops
    all_rtts = []
    for k in hop_keys:
        all_rtts.extend([r for r in history[k]["rtts"] if r is not None])
    if not all_rtts:
        return None
    ymax = max(all_rtts) * 1.15

    fig = plotille.Figure()
    fig.width   = GRAPH_WIDTH
    fig.height  = GRAPH_HEIGHT
    fig.x_label = "Elapsed (s)"
    fig.y_label = "RTT (ms)"
    fig.set_x_limits(min_=0, max_=max(all_times) - x0 if all_times else 1)
    fig.set_y_limits(min_=0, max_=ymax)

    for k in hop_keys:
        h         = history[k]
        hop_num   = h["hop"]
        hop_host  = h.get("host", "???")
        # Use short label: hop number + truncated host
        short     = hop_host[:20] if len(hop_host) > 20 else hop_host
        hop_label = f"Hop {hop_num}: {short}"

        pairs = [(t, r) for t, r in zip(h["times"], h["rtts"]) if r is not None]
        if len(pairs) < 2:
            continue
        xs = [t - x0 for t, _ in pairs]
        ys = [r      for _, r in pairs]
        fig.plot(xs, ys, label=hop_label)

    return fig.show()


def micron_page():
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    now_ts  = time.time()

    hosts = parse_rns_interfaces()

    # Run mtr and update histories before any output
    results = {}
    for (label, host) in hosts:
        mtr_data = run_mtr(host)
        hops     = extract_hops(mtr_data)
        history  = load_mtr_history(label)
        if hops:
            update_mtr_history(history, hops, now_ts)
            save_mtr_history(label, history)
        results[label] = (host, hops, history)

    # Split into hosts with graphable history vs those without
    graphable     = [(l, h) for l, h in hosts
                     if any(history.get("rtts") for history
                            in results[l][2].values())]
    not_graphable = [(l, h) for l, h in hosts if (l, h) not in graphable]

    # -------------------------------------------------------------------------
    print("#!c=0")
    print("`l`Ffd0MTR Per-Hop Latency`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`Ffd0Updated:`f   `F0fd{now_str}`f")
    print(f"`Ffd0MTR cycles:`f `F0fd{MTR_CYCLES} per host`f")
    if not hosts:
        print("`Ff00No interfaces found in reticulum config.`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    for (label, host) in hosts:
        host_str, hops, history = results[label]

        print()
        print(f"`Ffd0{label}`f  `F888({host_str})`f")

        if not hops:
            print("`Ff00  No mtr response — is mtr installed?`f")
            print("`F888  sudo apt install mtr-tiny`f")
        else:
            # Current hop table
            print()
            responding_hops = [h for h in hops if h["avg_ms"] is not None]
            silent_hops     = [h for h in hops if h["avg_ms"] is None]
            total_hops      = len(hops)
            dest_hop        = hops[-1] if hops else None

            if dest_hop and dest_hop["avg_ms"] is not None:
                rtt = dest_hop["avg_ms"]
                if rtt < 50:
                    colour = "`F0f2"
                elif rtt < 200:
                    colour = "`Ffd0"
                else:
                    colour = "`Ff00"
                print(f"`F888  Destination RTT:`f  {colour}{rtt:.1f} ms`f")

            print(f"`F888  Total hops:`f       `F0fd{total_hops}`f")
            if silent_hops:
                print(f"`F888  Silent hops:`f      `Ffd0{len(silent_hops)}`f  `F888(ICMP filtered)`f")

            print()
            print("`F888  Hop  RTT (ms)   Loss%  Host`f")
            print("`F888  ─────────────────────────────────────────`f")
            for hop in hops:
                hop_n    = hop["hop"]
                hop_host = hop["host"][:35]
                loss     = hop["loss_pct"]
                rtt      = hop["avg_ms"]

                if rtt is None:
                    rtt_str    = "`F888     ???`f"
                elif rtt < 50:
                    rtt_str    = f"`F0f2{rtt:8.1f}`f"
                elif rtt < 200:
                    rtt_str    = f"`Ffd0{rtt:8.1f}`f"
                else:
                    rtt_str    = f"`Ff00{rtt:8.1f}`f"

                if loss == 0.0:
                    loss_str   = f"`F0f2{loss:5.1f}`f"
                elif loss < 10.0:
                    loss_str   = f"`Ffd0{loss:5.1f}`f"
                else:
                    loss_str   = f"`Ff00{loss:5.1f}`f"

                host_colour = "`Ffff" if hop_host != "???" else "`F888"
                print(f"`F888  {hop_n:>2}`f   {rtt_str}  {loss_str}  {host_colour}{hop_host}`f")

        print()
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        graph_str = render_mtr_graph(label, history)
        if graph_str is None:
            print("`F888  Not enough data yet — reload to accumulate readings.`f")
        else:
            print("```")
            print(graph_str)
            print("```")

    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`F888Showing first {MAX_HOSTS} hosts from config. Edit MAX_HOSTS to change.`f")
    print("`F888Page re-executes on every visit (c=0).`f")
    print(f"`F888Data: {MTR_DATA_DIR}`f")
    print("`a")


if __name__ == "__main__":
    micron_page()
