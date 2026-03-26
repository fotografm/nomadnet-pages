#!/usr/bin/env python3
# =============================================================================
#  noise-logger.py  —  Reticulum RNode RF environment logger
#  Place at:  ~/noise-logger.py
#
#  Run once per minute via cron:
#    * * * * * /usr/bin/python3 /home/USER/noise-logger.py
#
#  Parses rnstatus output for the RNode LoRa Interface block and records:
#    - Noise Floor (dBm)          — always present when interface is Up
#    - Interference event (dBm)   — stored as null if no event in last 5 min
#    - Airtime 15s window (%)     — our own TX duty cycle, short window
#    - Channel Load 15s window (%) — all transmitters we can hear
#
#  Output: rolling JSON at ~/.nomadnetwork/rfdata/noise.json
#  Keeps the last MAX_SAMPLES samples (default 1440 = 24h at 1/min).
# =============================================================================

import os
import re
import json
import subprocess
import time

# =============================================================================
#  CONFIGURATION
# =============================================================================

# Full path to rnstatus binary in the reticulum venv
RNSTATUS = os.path.expanduser("~/reticulum-env/bin/rnstatus")

# Interface name as it appears inside brackets in rnstatus output
INTERFACE_NAME = "RNode LoRa Interface"

# Output data file
DATA_DIR  = os.path.expanduser("~/.nomadnetwork/rfdata")
DATA_FILE = os.path.join(DATA_DIR, "noise.json")

# How many samples to retain (1440 = 24 hours at 1 sample/minute)
MAX_SAMPLES = 1440

# Maximum age in seconds for an interference event to be considered "recent".
# Events older than this are stored as null (gap in the interference graph).
MAX_INTRFRNC_AGE = 300  # 5 minutes

# =============================================================================
#  HELPERS
# =============================================================================

def run_rnstatus():
    """Run rnstatus and return stdout as a string, or None on failure."""
    try:
        result = subprocess.run(
            [RNSTATUS],
            capture_output=True,
            text=True,
            timeout=15
        )
        return result.stdout
    except Exception:
        return None


def extract_interface_block(output, iface_name):
    """
    Find the block of rnstatus lines belonging to a named RNodeInterface.
    Returns a single string containing those lines, or None if not found.

    rnstatus output groups interface fields under a header line like:
        RNodeInterface[RNode LoRa Interface]
    followed by indented key/value lines until the next blank line or
    the next section header.
    """
    lines = output.splitlines()
    header = f"RNodeInterface[{iface_name}]"
    in_block = False
    block_lines = []

    for line in lines:
        if header in line:
            in_block = True
            block_lines.append(line)
            continue
        if in_block:
            # Stop at blank line or a new top-level section header
            if line.strip() == "" or (line and not line[0].isspace() and "[" in line):
                break
            block_lines.append(line)

    return "\n".join(block_lines) if block_lines else None


def parse_block(block):
    """
    Extract RF metrics from the RNode interface block.
    Returns a dict with keys: noise, intrfrnc, airtime_15s, chload_15s.
    Values that cannot be parsed are None.
    """
    result = {
        "noise":      None,
        "intrfrnc":   None,
        "airtime_15s": None,
        "chload_15s":  None,
    }

    # Noise Fl.:  -104 dBm
    m = re.search(r'Noise Fl\.\s*:\s*([-\d]+)\s*dBm', block)
    if m:
        result["noise"] = int(m.group(1))

    # Intrfrnc.:  -84 dBm 53s ago
    m = re.search(r'Intrfrnc\.\s*:\s*([-\d]+)\s*dBm\s+(\d+)s\s+ago', block)
    if m:
        age_secs = int(m.group(2))
        if age_secs <= MAX_INTRFRNC_AGE:
            result["intrfrnc"] = int(m.group(1))
        # else: leave as None — event is too old, leave a gap in the graph

    # Airtime:  6.27% (15s), 1.5% (1h)
    m = re.search(r'Airtime\s*:\s*([\d.]+)%\s*\(15s\)', block)
    if m:
        result["airtime_15s"] = float(m.group(1))

    # Ch. Load:  15.67% (15s), 14.67% (1h)
    m = re.search(r'Ch\.\s*Load\s*:\s*([\d.]+)%\s*\(15s\)', block)
    if m:
        result["chload_15s"] = float(m.group(1))

    return result


def load_data():
    """Load existing sample list from the JSON file, or return empty list."""
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
        except Exception:
            pass
    return []


def save_data(samples):
    """Save sample list to the JSON file, trimming to MAX_SAMPLES."""
    os.makedirs(DATA_DIR, exist_ok=True)
    samples = samples[-MAX_SAMPLES:]
    with open(DATA_FILE, "w") as f:
        json.dump(samples, f)


# =============================================================================
#  MAIN
# =============================================================================

def main():
    output = run_rnstatus()
    if not output:
        return  # rnsd not running or rnstatus failed — skip this sample

    block = extract_interface_block(output, INTERFACE_NAME)
    if not block:
        return  # Interface not found in output — skip

    metrics = parse_block(block)

    # Require at least noise floor to be present before recording a sample
    if metrics["noise"] is None:
        return

    sample = {
        "t":           int(time.time()),
        "noise":       metrics["noise"],
        "intrfrnc":    metrics["intrfrnc"],   # None = no recent event
        "airtime_15s": metrics["airtime_15s"],
        "chload_15s":  metrics["chload_15s"],
    }

    samples = load_data()
    samples.append(sample)
    save_data(samples)


if __name__ == "__main__":
    main()
