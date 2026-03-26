#!/usr/bin/python3
import sys
sys.path.insert(0, '/home/user/.venvs/rns-tools/lib/python3.10/site-packages')
import os, json, datetime

# =============================================================================
#  rf-noise.mu  —  Nomadnet page: noise floor graph only
#  Place at: ~/.nomadnetwork/storage/pages/rf-noise.mu
#  Data written by: ~/noise-logger.py (cron, every minute)
#  Browser: MeshChat built-in (not rBrowser)
# =============================================================================

DATA_FILE      = os.path.expanduser("~/.nomadnetwork/rfdata/noise.json")
DISPLAY_POINTS = 1440
GRAPH_WIDTH    = 60
GRAPH_HEIGHT   = 12
LABEL_W        = 6

samples_all = []
if os.path.exists(DATA_FILE):
    with open(DATA_FILE) as f:
        samples_all = json.load(f)
samples = samples_all[-DISPLAY_POINTS:]

now_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

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
    bucket_w  = t_span / plot_w
    buckets   = [[] for _ in range(plot_w)]
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

print("`Ffd0RF Noise Floor`f")
print(SEP)
print(f"`F888Time:`f      `Ffd0{now_str}`f")
print(f"`F888Interface:`f `F0fdRNode LoRa Interface`f  `F888({len(samples)} min window)`f")
print(SEP)

if len(samples) < 2:
    print("`F550No data yet — waiting for cron logger.`f")
else:
    latest    = samples[-1]
    noise_str = f"{latest['noise']} dBm" if latest.get("noise") is not None else "N/A"
    intr_str  = (f"`F500{latest['intrfrnc']} dBm`f"
                 if latest.get("intrfrnc") is not None else "`F0f2none recent`f")
    air_str   = f"{latest['airtime_15s']:.1f}%" if latest.get("airtime_15s") is not None else "N/A"
    ch_str    = f"{latest['chload_15s']:.1f}%"  if latest.get("chload_15s")  is not None else "N/A"

    print(f"`F888Noise floor:`f    `F0fd{noise_str}`f  `F888Interference:`f {intr_str}")
    print(f"`F888Airtime (15s):`f  `F0f2{air_str}`f  `F888Ch. Load (15s):`f `F550{ch_str}`f")
    print(SEP)

    xs_n = [s["t"]     for s in samples if s.get("noise") is not None]
    ys_n = [s["noise"] for s in samples if s.get("noise") is not None]
    ascii_graph(xs_n, ys_n, "Noise Floor (dBm) — 24h")
    print(SEP)

print(f"`F888Samples stored: {len(samples_all)} / 1440`f")
