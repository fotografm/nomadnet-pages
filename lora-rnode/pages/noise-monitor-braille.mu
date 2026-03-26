#!/usr/bin/python3
import sys
sys.path.insert(0, '/home/user/.venvs/rns-tools/lib/python3.10/site-packages')
import os, json, datetime

# =============================================================================
#  noise-monitor-braille.mu  —  Nomadnet page: RNode RF environment graphs
#  Place at: ~/.nomadnetwork/storage/pages/noise-monitor-braille.mu
#  Data written by: ~/noise-logger.py (cron, every minute)
#  Browser: MeshChat built-in (not rBrowser)
# =============================================================================

DATA_FILE      = os.path.expanduser("~/.nomadnetwork/rfdata/noise.json")
DISPLAY_POINTS = 1440
GRAPH_WIDTH    = 72    # total chars including Y label + axis char
GRAPH_HEIGHT   = 12    # rows of plot area
LABEL_W        = 6     # chars for Y axis label e.g. "  -104"

# ── Load data ─────────────────────────────────────────────────────────────────
samples_all = []
if os.path.exists(DATA_FILE):
    with open(DATA_FILE) as f:
        samples_all = json.load(f)
samples = samples_all[-DISPLAY_POINTS:]

now_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

# ── ASCII graph renderer ──────────────────────────────────────────────────────
# Each column gets at most one * by binning xs/ys into plot_w buckets and
# averaging the y values in each bucket. This guarantees a clean single-pixel
# line regardless of how many raw samples fall in the same column.
# scatter=True skips the binning so sparse events remain as individual dots.
def ascii_graph(xs, ys, title, scatter=False):
    if len(xs) < 2:
        print(f"  {title} — not enough data yet")
        return

    plot_w = GRAPH_WIDTH - LABEL_W - 1   # chars available for the data area
    plot_h = GRAPH_HEIGHT

    t_min  = xs[0]
    t_max  = xs[-1]
    t_span = max(t_max - t_min, 1)

    # ── Bin into exactly plot_w buckets (one per column) ─────────────────────
    if scatter:
        # For scatter plots keep raw points; multiple per column is fine
        binned_xs = xs
        binned_ys = ys
    else:
        bucket_w  = t_span / plot_w
        buckets   = [[] for _ in range(plot_w)]
        for x, y in zip(xs, ys):
            idx = min(int((x - t_min) / bucket_w), plot_w - 1)
            buckets[idx].append(y)
        binned_xs, binned_ys = [], []
        for i, vals in enumerate(buckets):
            if vals:
                binned_xs.append(t_min + (i + 0.5) * bucket_w)
                binned_ys.append(sum(vals) / len(vals))

    # ── Y axis range ──────────────────────────────────────────────────────────
    mid   = (min(binned_ys) + max(binned_ys)) / 2.0
    span  = max(max(binned_ys) - min(binned_ys), plot_h)
    vmin  = mid - span / 2.0 - 1
    vmax  = mid + span / 2.0 + 1

    def to_col(t):
        return min(int((t - t_min) / t_span * plot_w), plot_w - 1)

    def to_row(v):
        clamped = max(vmin, min(vmax, v))
        return min(int((vmax - clamped) / (vmax - vmin) * plot_h), plot_h - 1)

    # ── Build grid ────────────────────────────────────────────────────────────
    grid = [[" "] * plot_w for _ in range(plot_h)]
    for x, y in zip(binned_xs, binned_ys):
        c = to_col(x)
        r = to_row(y)
        grid[r][c] = "*"

    # ── Print title + rows ────────────────────────────────────────────────────
    print(f"`Ffd0{title}`f")
    for r in range(plot_h):
        y_val = vmax - (r / (plot_h - 1)) * (vmax - vmin)
        label = f"{int(round(y_val)):>{LABEL_W}}"
        print(label + "│" + "".join(grid[r]))

    # ── X axis line ───────────────────────────────────────────────────────────
    print(" " * LABEL_W + "└" + "─" * plot_w)

    # ── X time labels: start, mid, end ───────────────────────────────────────
    t_start = datetime.datetime.utcfromtimestamp(t_min).strftime("%H:%M")
    t_mid   = datetime.datetime.utcfromtimestamp((t_min + t_max) / 2).strftime("%H:%M")
    t_end   = datetime.datetime.utcfromtimestamp(t_max).strftime("%H:%M")
    gap_l   = plot_w // 2 - len(t_start) - len(t_mid) // 2
    gap_r   = plot_w - plot_w // 2 - len(t_end)
    print(" " * (LABEL_W + 1) +
          t_start +
          " " * max(1, gap_l) + t_mid +
          " " * max(1, gap_r) + t_end)

# ── Page header ───────────────────────────────────────────────────────────────
print("`Ffd0RF Environment Monitor 24 hr Plots`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`F888Time:`f      `Ffd0{now_str}`f")
print(f"`F888Interface:`f `F0fdRNode LoRa Interface`f  `F888({len(samples)} min window)`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

if len(samples) < 2:
    print("`F550No data yet — waiting for cron logger.`f")
    print("`F888Check crontab: * * * * * /usr/bin/python3 ~/noise-logger.py`f")
else:
    # ── Latest readings ───────────────────────────────────────────────────────
    latest    = samples[-1]
    noise_str = f"{latest['noise']} dBm" if latest.get("noise") is not None else "N/A"
    intr_str  = (f"`F500{latest['intrfrnc']} dBm`f"
                 if latest.get("intrfrnc") is not None else "`F0f2none recent`f")
    air_str   = f"{latest['airtime_15s']:.1f}%" if latest.get("airtime_15s") is not None else "N/A"
    ch_str    = f"{latest['chload_15s']:.1f}%"  if latest.get("chload_15s")  is not None else "N/A"

    print(f"`F888Noise floor:`f    `F0fd{noise_str}`f  `F888Interference:`f {intr_str}")
    print(f"`F888Airtime (15s):`f  `F0f2{air_str}`f  `F888Ch. Load (15s):`f `F550{ch_str}`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # ── Graph 1: Noise Floor ──────────────────────────────────────────────────
    xs_n = [s["t"]     for s in samples if s.get("noise") is not None]
    ys_n = [s["noise"] for s in samples if s.get("noise") is not None]
    ascii_graph(xs_n, ys_n, "Noise Floor (dBm)")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # ── Graph 2: Interference events ─────────────────────────────────────────
    xs_i = [s["t"]        for s in samples if s.get("intrfrnc") is not None]
    ys_i = [s["intrfrnc"] for s in samples if s.get("intrfrnc") is not None]
    if len(xs_i) >= 2:
        ascii_graph(xs_i, ys_i, "Interference Events (dBm)")
        print("`F888Gaps = no interference detected in that period`f")
    else:
        print("`Ffd0Interference Events`f")
        print("`F0f2No interference events in current window.`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # ── Graph 3: Our Airtime (%) ──────────────────────────────────────────────
    xs_a = [s["t"]           for s in samples if s.get("airtime_15s") is not None]
    ys_a = [s["airtime_15s"] for s in samples if s.get("airtime_15s") is not None]
    ascii_graph(xs_a, ys_a, "Our Airtime / TX Duty Cycle (%) 15s")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # ── Graph 4: Channel Load (%) ─────────────────────────────────────────────
    xs_ch = [s["t"]          for s in samples if s.get("chload_15s") is not None]
    ys_ch = [s["chload_15s"] for s in samples if s.get("chload_15s") is not None]
    ascii_graph(xs_ch, ys_ch, "Total Channel Load (%) 15s")
    print("`F888Includes all heard transmissions — our TX plus all other nodes`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

print(f"`F888Total samples stored: {len(samples_all)} / 1440`f")
