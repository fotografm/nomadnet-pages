#!/usr/bin/python3
import sys
sys.path.insert(0, '/home/user/.venvs/rns-tools/lib/python3.10/site-packages')
import os, json, datetime, plotille

# =============================================================================
#  rssi-monitor.mu  —  Nomadnet page: per-node RSSI graphs from LoRa announces
#  Place at: ~/.nomadnetwork/storage/pages/rssi-monitor.mu
#  Data written by: ~/rssi-logger.py (systemd service)
#  One graph per node, auto-discovered from ~/.nomadnetwork/rssidata/*.json
# =============================================================================

DATA_DIR       = os.path.expanduser("~/.nomadnetwork/rssidata")
NAMES_FILE     = os.path.join(DATA_DIR, "names.json")
DISPLAY_POINTS = 1440   # up to 24h of samples per node
GRAPH_WIDTH    = 60
GRAPH_HEIGHT   = 10

now_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

# Load hash -> name map (written by names-resolver.py)
names = {}
if os.path.exists(NAMES_FILE):
    try:
        with open(NAMES_FILE) as f:
            names = json.load(f)
    except Exception:
        pass

# ── Axis formatter: epoch -> HH:MM on X, integer on Y ─────────────────────────
def fmt(val, chars, delta, left=False):
    if val > 1_000_000_000:
        dt = datetime.datetime.utcfromtimestamp(val)
        label = dt.strftime("%H:%M") if delta < 86400 else dt.strftime("%a %H:%M")
        return label[:chars].rjust(chars)
    return str(int(round(val)))[:chars].rjust(chars)

# ── Page header ───────────────────────────────────────────────────────────────
print("`Ffd0RNode LoRa RSSI Monitor - all times are UTC. Only showing nodes which are 1 hop away. ie. Direct`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`F888Time:`f `Ffd0{now_str}`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# ── Discover node files ───────────────────────────────────────────────────────
if not os.path.exists(DATA_DIR):
    print("`F550No data directory found.`f")
    print("`F888Check rssi-logger service: systemctl status rssi-logger`f")
else:
    node_files = sorted([
        f for f in os.listdir(DATA_DIR) if f.endswith(".json")
    ])

    if not node_files:
        print("`F550No node data yet — waiting for LoRa announces.`f")
        print("`F888Check rssi-logger service: systemctl status rssi-logger`f")
    else:
        print(f"`F888Nodes tracked: `F0f2{len(node_files)}`f")
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        for fname in node_files:
            node_hash = fname[:-5]          # strip .json
            short     = node_hash[:16]      # first 16 chars for display

            path = os.path.join(DATA_DIR, fname)
            try:
                with open(path) as f:
                    all_samples = json.load(f)
            except Exception:
                continue

            # Skip nodes with no resolved name — these are non-primary
            # LXMF destinations (propagation, pages etc.) with no app_data
            if node_hash not in names:
                continue

            samples = all_samples[-DISPLAY_POINTS:]
            if len(samples) < 2:
                print(f"`Ffd0{short}`f  `F888(1 sample — waiting for more)`f")
                print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                continue

            # ── Latest values ─────────────────────────────────────────────────
            latest = samples[-1]
            first  = all_samples[0]
            last_dt  = datetime.datetime.utcfromtimestamp(latest["t"])
            first_dt = datetime.datetime.utcfromtimestamp(first["t"])
            last_str  = last_dt.strftime("%Y-%m-%d %H:%M UTC")
            first_str = first_dt.strftime("%Y-%m-%d %H:%M UTC")
            total     = len(all_samples)

            label = names.get(node_hash, short)
            print(f"`Ffd0{label}`f  `F888[{short}]`f")
            print(f"`F888First seen:`f `F0fd{first_str}`f  "
                  f"`F888Announces:`f `F0f2{total}`f")
            print(f"`F888Last seen:`f  `F0fd{last_str}`f  "
                  f"`F888RSSI:`f `F0fd{latest['rssi']} dBm`f  "
                  f"`F888SNR:`f `F0fd{latest['snr']} dB`f  "
                  f"`F888Hops:`f `F0fd{latest['hops']}`f")

            # ── Build series ──────────────────────────────────────────────────
            xs   = [s["t"]    for s in samples]
            ys_r = [s["rssi"] for s in samples]
            ys_s = [s["snr"]  for s in samples]

            # ── RSSI graph ────────────────────────────────────────────────────
            # Enforce minimum Y span of GRAPH_HEIGHT dBm so each row maps to
            # a unique 1 dBm step and labels never repeat.
            r_mid = (min(ys_r) + max(ys_r)) / 2
            r_span = max(max(ys_r) - min(ys_r), GRAPH_HEIGHT)
            y_min = int(r_mid - r_span / 2) - 1
            y_max = int(r_mid + r_span / 2) + 1

            fig = plotille.Figure()
            fig.width   = GRAPH_WIDTH
            fig.height  = GRAPH_HEIGHT
            fig.x_label = "Time (UTC)"
            fig.y_label = "RSSI dBm"
            fig.set_x_limits(min_=min(xs), max_=max(xs))
            fig.set_y_limits(min_=y_min, max_=y_max)
            fig.register_label_formatter(float, fmt)
            fig.register_label_formatter(int,   fmt)
            fig.plot(xs, ys_r, label="RSSI", lc="cyan")

            print(fig.show(legend=False))

            # ── SNR graph ─────────────────────────────────────────────────────
            # Same minimum span logic for SNR.
            s_mid = (min(ys_s) + max(ys_s)) / 2
            s_span = max(max(ys_s) - min(ys_s), GRAPH_HEIGHT)
            y2_min = int(s_mid - s_span / 2) - 1
            y2_max = int(s_mid + s_span / 2) + 1

            fig2 = plotille.Figure()
            fig2.width   = GRAPH_WIDTH
            fig2.height  = GRAPH_HEIGHT
            fig2.x_label = "Time (UTC)"
            fig2.y_label = "SNR dB"
            fig2.set_x_limits(min_=min(xs), max_=max(xs))
            fig2.set_y_limits(min_=y2_min, max_=y2_max)
            fig2.register_label_formatter(float, fmt)
            fig2.register_label_formatter(int,   fmt)
            fig2.plot(xs, ys_s, label="SNR", lc="green")

            print(fig2.show(legend=False))
            print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

print(f"`F888Data dir: {DATA_DIR}`f")
