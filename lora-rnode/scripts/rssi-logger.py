#!/usr/bin/env python3
# =============================================================================
#  rssi-logger.py  —  RNode LoRa announce RSSI/SNR logger daemon
#  Place at: ~/rssi-logger.py
#  Run as:   systemd service (rssi-logger.service)
#
#  Tails the rnsd systemd journal and extracts RSSI and SNR from every
#  announce received on the RNode LoRa Interface. Creates one JSON file
#  per source node hash, auto-discovered — no configuration needed.
#
#  Deduplication: only the first reception of each announce is recorded.
#  Subsequent rebroadcasts of the same announce (arriving within 60s) are
#  ignored, preventing sawtooth artifacts from intermediate nodes relaying
#  the same packet at different RSSI levels.
#
#  Output: ~/.nomadnetwork/rssidata/<hash>.json
#  Each file is a list of samples:
#    {"t": epoch, "rssi": -102, "snr": 2.0, "hops": 1}
#
#  Keeps the last MAX_SAMPLES entries per node (default 2000).
# =============================================================================

import os
import re
import json
import subprocess
import time
import datetime
import sys

# =============================================================================
#  CONFIGURATION
# =============================================================================

DATA_DIR    = os.path.expanduser("~/.nomadnetwork/rssidata")
MAX_SAMPLES = 2000
IFACE_NAME  = "RNode LoRa Interface"
RNSD_UNIT   = "rnsd"

# Minimum seconds between recorded samples for the same node.
# Rebroadcasts of the same announce arrive within a few seconds;
# 60s ensures only the first reception per announce cycle is kept.
DEDUP_WINDOW = 60

# =============================================================================
#  REGEX
# =============================================================================

# Matches both direct and relayed announce lines, e.g.:
#   Valid announce for <HASH> 1 hops away, received on RNodeInterface[RNode LoRa Interface] [RSSI -102dBm, SNR 1.0dB]
#   Valid announce for <HASH> 1 hops away, received via <HASH> on RNodeInterface[RNode LoRa Interface] [RSSI -102dBm, SNR 0.5dB]

ANNOUNCE_RE = re.compile(
    r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]'
    r'.*?Valid announce for <([0-9a-f]+)>'
    r' (\d+) hops? away'
    r'.*?RNodeInterface\[' + re.escape(IFACE_NAME) + r'\]'
    r'.*?\[RSSI ([-\d]+)dBm, SNR ([\d.\-]+)dB\]'
)

# =============================================================================
#  HELPERS
# =============================================================================

def load_node(node_hash):
    path = os.path.join(DATA_DIR, f"{node_hash}.json")
    if os.path.exists(path):
        try:
            with open(path) as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
        except Exception:
            pass
    return []


def save_node(node_hash, samples):
    os.makedirs(DATA_DIR, exist_ok=True)
    path = os.path.join(DATA_DIR, f"{node_hash}.json")
    samples = samples[-MAX_SAMPLES:]
    with open(path, "w") as f:
        json.dump(samples, f)


def parse_timestamp(ts_str):
    try:
        dt = datetime.datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        return int(dt.timestamp())
    except Exception:
        return int(time.time())


def record_sample(node_hash, epoch, rssi, snr, hops):
    samples = load_node(node_hash)
    samples.append({"t": epoch, "rssi": rssi, "snr": snr, "hops": hops})
    save_node(node_hash, samples)


# =============================================================================
#  MAIN
# =============================================================================

def main():
    os.makedirs(DATA_DIR, exist_ok=True)

    # seen[node_hash] = epoch of last recorded sample for deduplication
    seen = {}

    cmd = [
        "journalctl", "-u", RNSD_UNIT,
        "-f", "-n", "0", "--output=cat",
    ]

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    try:
        for line in proc.stdout:
            line = line.rstrip()
            m = ANNOUNCE_RE.search(line)
            if not m:
                continue

            ts_str    = m.group(1)
            node_hash = m.group(2)
            hops      = int(m.group(3))
            rssi      = int(m.group(4))
            snr       = float(m.group(5))
            epoch     = parse_timestamp(ts_str)

            # Skip rebroadcasts of the same announce
            if epoch - seen.get(node_hash, 0) < DEDUP_WINDOW:
                continue

            seen[node_hash] = epoch
            if hops == 1:
                record_sample(node_hash, epoch, rssi, snr, hops)

    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
