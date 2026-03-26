#!/home/user/.venvs/pingtools/bin/python3
# =============================================================================
#  announce-rate.mu  —  Nomadnet page: Reticulum announce rate over time
#  Place in: ~/.nomadnetwork/storage/pages/announce-rate.mu
#
#  Dependencies:
#    ~/.venvs/pingtools/bin/pip install plotille
#
#  Also requires announce-listener.py to be running in the background.
#  Start it once after nomadnet is up:
#      ~/.nomadnetwork/announce-listener.py &
#
#  How it works:
#    announce-listener.py hooks into the running Reticulum instance and writes
#    one timestamped log line to ~/.nomadnetwork/announce.log for every announce
#    packet received.  This page reads the tail of that log, bins the events
#    into fixed-width time buckets (default 5 min), and plots the resulting
#    histogram as an ASCII line graph via plotille.
#
#  Graph axes:
#    X — wall-clock time (HH:MM for windows ≤24 h, "Mon HH:MM" for longer).
#        The bucket keys are already Unix epoch timestamps, so they are passed
#        directly to plotille and a unified formatter converts them to time
#        strings on the X axis and to plain integers on the Y axis, keyed on
#        value magnitude (epoch timestamps are ~1.7×10⁹, counts are small).
#    Y — number of announces per bucket, displayed as whole integers.
# =============================================================================

import os
import re
import datetime
import time

# =============================================================================
#  USER CONFIGURATION
# =============================================================================

# Plotille canvas dimensions in character cells.
GRAPH_WIDTH  = 60
GRAPH_HEIGHT = 15

# Width of each histogram bucket in minutes.  Every announce within the same
# BUCKET_MINUTES window is counted as a single bar in the graph.
BUCKET_MINUTES = 5

# Number of buckets to show.  Total visible window = BUCKETS × BUCKET_MINUTES.
# Default: 60 buckets × 5 min = 5 hours of history.
BUCKETS = 60

# How many bytes to read from the tail of the log file on each page load.
# Reading the whole file would be slow once it grows large.
LOG_TAIL_BYTES = 512 * 1024   # 512 KB

# Path to the announce log written by announce-listener.py.
ANNOUNCE_LOG = os.path.expanduser("~/.nomadnetwork/announce.log")

# =============================================================================
#  END OF USER CONFIGURATION
# =============================================================================

# Log line format written by announce-listener.py:
#   2026-02-25 18:03:42 a1b2c3d4e5f6...  [optional app_data]
# We only need the timestamp; the destination hash is captured but not used.
LOG_RE = re.compile(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+([0-9a-f<>:]+)'
)


# ---------------------------------------------------------------------------
#  Plotille axis formatters
# ---------------------------------------------------------------------------

def _time_label_formatter(val, chars, delta, left=False):
    """
    Plotille axis formatter for Unix epoch X values.

    Converts the epoch float to a local wall-clock string:
      - Window ≤ 24 hours  →  HH:MM         (e.g. "14:37")
      - Window >  24 hours  →  ddd HH:MM    (e.g. "Mon 14:37")

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    dt  = datetime.datetime.fromtimestamp(val)
    fmt = "%H:%M" if delta <= 86400 else "%a %H:%M"
    return '{:>{w}}'.format(dt.strftime(fmt), w=chars)


def _int_label_formatter(val, chars, delta, left=False):
    """
    Plotille axis formatter that renders small float values (announce counts)
    as whole integers, e.g. "42" instead of "42.00".

    Signature matches plotille's Formatter type:
        (val: float, chars: int, delta: float, left: bool = False) -> str
    """
    return '{:>{w}d}'.format(int(round(val)), w=chars)


def _unified_formatter(val, chars, delta, left=False):
    """
    Single formatter registered for the float type on every Figure.

    plotille calls this for both X and Y tick labels.  We distinguish them
    by magnitude: epoch timestamps are ~1.7×10⁹, while announce counts are
    small integers.  Anything above 1e8 is treated as an epoch and formatted
    as a time string; anything smaller is formatted as a plain integer.
    """
    if val > 1e8:
        return _time_label_formatter(val, chars, delta, left)
    return _int_label_formatter(val, chars, delta, left)


# ---------------------------------------------------------------------------
#  Log reading and parsing
# ---------------------------------------------------------------------------

def tail_log(path, nbytes):
    """
    Read up to nbytes from the end of the log file at path and return the
    content as a string.  Seeks past any partial line created by the seek
    so that the first line returned is always complete.
    Returns an empty string if the file does not exist or cannot be read.
    """
    if not os.path.exists(path):
        return ""
    try:
        size = os.path.getsize(path)
        with open(path, 'r', errors='replace') as f:
            if size > nbytes:
                f.seek(size - nbytes)
                f.readline()   # discard the partial first line after the seek
            return f.read()
    except Exception:
        return ""


def bucket_floor(dt, bucket_minutes):
    """
    Floor a datetime to the start of its enclosing time bucket and return
    the result as a Unix timestamp float.

    Example with BUCKET_MINUTES=5:
        18:07:42  →  18:05:00  →  epoch float for that moment
    """
    total_secs  = dt.hour * 3600 + dt.minute * 60 + dt.second
    bucket_secs = (total_secs // (bucket_minutes * 60)) * (bucket_minutes * 60)
    floored = dt.replace(
        hour        = bucket_secs // 3600,
        minute      = (bucket_secs % 3600) // 60,
        second      = 0,
        microsecond = 0
    )
    return floored.timestamp()


def parse_log(log_text, bucket_minutes):
    """
    Parse the announce log text and bin events into time buckets.

    Returns:
        counts   — {bucket_unix_ts: int}  announce count per bucket
        first_dt — datetime of the first log entry in the tail, or None
        last_dt  — datetime of the most recent log entry in the tail, or None
    """
    counts   = {}
    first_dt = None
    last_dt  = None

    for line in log_text.splitlines():
        m = LOG_RE.match(line.strip())
        if not m:
            continue
        try:
            dt  = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            key = bucket_floor(dt, bucket_minutes)
            counts[key] = counts.get(key, 0) + 1
            if first_dt is None:
                first_dt = dt
            last_dt = dt
        except Exception:
            continue

    return counts, first_dt, last_dt


def build_series(counts, bucket_minutes, num_buckets):
    """
    Build aligned (xs, ys) lists for the num_buckets most recent buckets,
    padding with zeros for any bucket that has no announces.

    xs — list of Unix epoch floats (bucket start times), used directly as
         plotille X values so the unified formatter can render wall-clock times.
    ys — list of announce counts for each bucket.
    """
    now     = datetime.datetime.now()
    now_key = bucket_floor(now, bucket_minutes)
    step    = bucket_minutes * 60   # bucket width in seconds

    # Generate bucket keys from oldest to newest.
    keys = [now_key - (num_buckets - 1 - i) * step for i in range(num_buckets)]
    ys   = [counts.get(k, 0) for k in keys]

    # Return the bucket epoch timestamps as X values — NOT elapsed offsets.
    # This lets the formatter show real clock times on the X axis.
    xs = keys
    return xs, ys


# ---------------------------------------------------------------------------
#  Micron page output
# ---------------------------------------------------------------------------

def micron_page():
    """
    Main entry point.  Reads and parses the announce log, builds the bucketed
    time series, then emits a Nomadnet micron-formatted page to stdout.

    Colour palette:
        `Ffd0  gold   — section headings / stat labels
        `F0f2  green  — dividers
        `Ff00  red    — errors / missing log
        `F0fd  cyan   — numeric values / log path
        `F888  grey   — secondary / dim labels
        `Ffff  white  — user-facing command text
    """
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    log_text              = tail_log(ANNOUNCE_LOG, LOG_TAIL_BYTES)
    counts, first_dt, last_dt = parse_log(log_text, BUCKET_MINUTES)

    xs, ys     = build_series(counts, BUCKET_MINUTES, BUCKETS)
    total      = sum(counts.values())
    peak       = max(ys) if ys else 0
    # Use the last 12 buckets (= 1 hour at 5-min buckets) as the "recent" window.
    recent     = ys[-12:]
    recent_avg = sum(recent) / len(recent) if recent else 0

    # --- Page header ---
    # c=0 tells Nomadnet to re-execute this script on every visit, never cache.
    print("#!c=0")
    print("`l`Ffd0Reticulum Announce Rate`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`Ffd0Updated:`f    `F0fd{now_str}`f")
    print(f"`Ffd0Log file:`f   `F888{ANNOUNCE_LOG}`f")

    # Bail out early if the log file hasn't been created yet.
    if not os.path.exists(ANNOUNCE_LOG):
        print()
        print("`Ff00announce.log not found.`f")
        print("`F888Start the listener daemon first:`f")
        print("`Ffff  ~/.nomadnetwork/announce-listener.py &`f")
        print("`a")
        return

    log_size = os.path.getsize(ANNOUNCE_LOG)
    print(f"`Ffd0Log size:`f   `F0fd{log_size // 1024} KB`f")

    # Bail out early if the log tail contained no parseable announce events.
    if total == 0:
        print()
        print("`Ff00No announce events found in log tail.`f")
        print("`F888The listener may have just started — wait a moment and reload.`f")
        print("`a")
        return

    # Show the time range covered by the log tail that was read.
    if first_dt and last_dt:
        print(
            f"`Ffd0Log spans:`f  "
            f"`F0fd{first_dt.strftime('%Y-%m-%d %H:%M')} "
            f"`F888→`f "
            f"`F0fd{last_dt.strftime('%Y-%m-%d %H:%M')}`f"
        )

    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()
    print(f"`Ffd0Window:`f     `F0fd{BUCKETS * BUCKET_MINUTES} min  `F888({BUCKET_MINUTES}-min buckets)`f")
    print(f"`Ffd0Total:`f      `F0fd{total} announces in log tail`f")
    print(f"`Ffd0Peak:`f       `F0fd{peak} per {BUCKET_MINUTES}-min bucket`f")
    print(f"`Ffd0Recent avg:`f `F0fd{recent_avg:.1f} per {BUCKET_MINUTES}-min bucket`f")

    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # --- Graph ---
    try:
        import plotille

        x_min = min(xs)
        x_max = max(xs)
        if x_max == x_min:
            x_max = x_min + 1

        fig = plotille.Figure()
        fig.width   = GRAPH_WIDTH
        fig.height  = GRAPH_HEIGHT
        fig.x_label = f"Time  [{BUCKET_MINUTES}-min buckets]"
        fig.y_label = "Announces"
        fig.set_x_limits(min_=x_min, max_=x_max)
        fig.set_y_limits(min_=0, max_=peak * 1.15 if peak > 0 else 1)

        # Register the unified formatter:
        #   - epoch-scale X values  →  wall-clock HH:MM (or "Mon HH:MM")
        #   - small Y values        →  plain integer announce counts
        fig.register_label_formatter(float, _unified_formatter)

        fig.plot(xs, ys, label="Announces/bucket")

        # The ``` fence renders the graph in a fixed-width block in Nomadnet.
        print("```")
        print(fig.show())
        print("```")

    except ImportError as e:
        print(f"`Ff00plotille import failed: {e}`f")

    # --- Page footer ---
    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("`F888Page re-executes on every visit (c=0).`f")
    print(f"`F888Log tail: {LOG_TAIL_BYTES // 1024} KB  |  Listener: announce-listener.py`f")
    print("`a")


if __name__ == "__main__":
    micron_page()
