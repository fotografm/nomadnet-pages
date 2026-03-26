#!/usr/bin/python3
import sys
sys.path.insert(0, '/home/user/.venvs/rns-tools/lib/python3.10/site-packages')
import os, json, datetime

# =============================================================================
#  rf-rssi.mu  —  Nomadnet page: per-node RSSI graphs (no SNR)
#  Place at: ~/.nomadnetwork/storage/pages/rf-rssi.mu
#  Data written by: ~/rssi-logger.py (systemd service)
#  One RSSI graph per named 1-hop node
# =============================================================================

DATA_DIR       = os.path.expanduser("~/.nomadnetwork/rssidata")
NAMES_FILE     = os.path.join(DATA_DIR, "names.json")
DISPLAY_POINTS = 1440
GRAPH_WIDTH    = 60
GRAPH_HEIGHT   = 10
LABEL_W        = 6

now_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

names = {}
if os.path.exists(NAMES_FILE):
    try:
        with open(NAMES_FILE) as f:
            names = json.load(f)
    except Exception:
        pass

def fmt_dt(epoch):
    return datetime.datetime.utcfromtimestamp(epoch).strftime("%H:%M")

def ascii_graph(xs, ys, title):
    if len(xs) < 2:
        print(f"  {title} — not enough data yet")
        return
    plot_w = GRAPH_WIDTH - LABEL_W - 1
    plot_h = GRAPH_HEIGHT
    t_min  = xs[0]
    t_max  = xs[-1]
    t_span = max(t_max - t_min, 1)

    # Bin into one bucket per column
    bucket_w = t_span / plot_w
    buckets  = [[] for _ in range(plot_w)]
    for x, y in zip(xs, ys):
        idx = min(int((x - t_min) / bucket_w), plot_w - 1)
        buckets[idx].append(y)
    bxs, bys = [], []
    for i, vals in enumerate(buckets):
        if vals:
            bxs.append(t_min + (i + 0.5) * bucket_w)
            bys.append(sum(vals) / len(vals))

    mid  = (min(bys) + max(bys)) / 2.0
    span = max(max(bys) - min(bys), plot_h)
    vmin = mid - span / 2.0 - 1
    vmax = mid + span / 2.0 + 1

    def to_col(t):
        return min(int((t - t_min) / t_span * plot_w), plot_w - 1)
    def to_row(v):
        clamped = max(vmin, min(vmax, v))
        return min(int((vmax - clamped) / (vmax - vmin) * plot_h), plot_h - 1)

    grid = [[" "] * plot_w for _ in range(plot_h)]
    for x, y in zip(bxs, bys):
        grid[to_row(y)][to_col(x)] = "*"

    print(f"`Ffd0{title}`f")
    for r in range(plot_h):
        y_val = vmax - (r / (plot_h - 1)) * (vmax - vmin)
        print(f"{int(round(y_val)):>{LABEL_W}}│" + "".join(grid[r]))
    print(" " * LABEL_W + "└" + "─" * plot_w)

    t_start = fmt_dt(t_min)
    t_mid   = fmt_dt((t_min + t_max) / 2)
    t_end   = fmt_dt(t_max)
    gap_l   = plot_w // 2 - len(t_start) - len(t_mid) // 2
    gap_r   = plot_w - plot_w // 2 - len(t_end)
    print(" " * (LABEL_W + 1) +
          t_start + " " * max(1, gap_l) +
          t_mid   + " " * max(1, gap_r) + t_end)

SEP = "`F0f2" + "━" * 60 + "`f"

print("`Ffd0RNode LoRa — Node RSSI`f")
print(SEP)
print(f"`F888Time:`f `Ffd0{now_str}`f")
print(SEP)

if not os.path.exists(DATA_DIR):
    print("`F550No data directory found.`f")
else:
    node_files = sorted([
        f for f in os.listdir(DATA_DIR)
        if f.endswith(".json") and f != "names.json" and f != "names_times.json"
    ])

    if not node_files:
        print("`F550No node data yet — waiting for LoRa announces.`f")
    else:
        shown = 0
        for fname in node_files:
            node_hash = fname[:-5]
            if node_hash not in names:
                continue

            path = os.path.join(DATA_DIR, fname)
            try:
                with open(path) as f:
                    all_samples = json.load(f)
            except Exception:
                continue

            samples = all_samples[-DISPLAY_POINTS:]
            if len(samples) < 2:
                continue

            shown += 1
            latest    = samples[-1]
            first     = all_samples[0]
            label     = names[node_hash]
            short     = node_hash[:16]
            last_str  = datetime.datetime.utcfromtimestamp(latest["t"]).strftime("%Y-%m-%d %H:%M UTC")
            first_str = datetime.datetime.utcfromtimestamp(first["t"]).strftime("%Y-%m-%d %H:%M UTC")
            total     = len(all_samples)

            print(f"`Ffd0{label}`f  `F888[{short}]`f")
            print(f"`F888First:`f `F0fd{first_str}`f  `F888Last:`f `F0fd{last_str}`f  "
                  f"`F888Count:`f `F0f2{total}`f")
            print(f"`F888Latest RSSI:`f `F0fd{latest['rssi']} dBm`f  "
                  f"`F888SNR:`f `F0fd{latest['snr']} dB`f  "
                  f"`F888Hops:`f `F0fd{latest['hops']}`f")

            xs   = [s["t"]    for s in samples]
            ys_r = [s["rssi"] for s in samples]
            ascii_graph(xs, ys_r, "RSSI (dBm)")
            print(SEP)

        if shown == 0:
            print("`F550No named 1-hop nodes with data yet.`f")
            print(SEP)

print(f"`F888Data dir: {DATA_DIR}`f")

