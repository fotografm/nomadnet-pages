#!/usr/bin/env python3
# =============================================================================
#  names-resolver.py  —  Reticulum announce name resolver daemon
#  Place at: ~/names-resolver.py
#  Run as:   systemd service (names-resolver.service)
#
#  Connects to the shared rnsd instance via the RNS Python API and listens
#  for all announces. When app_data is present and decodable as UTF-8, saves:
#    ~/.nomadnetwork/rssidata/names.json       hash -> name
#    ~/.nomadnetwork/rssidata/names_times.json hash -> {first_seen, last_seen}
#
#  names.json is read by rssi-monitor.mu and names.mu.
#  names_times.json is read only by names.mu for first/last seen timestamps
#  for nodes that have no RSSI data file (e.g. local or multi-hop nodes).
#  All other scripts (rssi-logger, noise-logger, graph pages) are unaffected.
# =============================================================================

import os
import sys
import json
import time

# Use the reticulum venv
sys.path.insert(0, '/home/user/reticulum-env/lib/python3.10/site-packages')

import RNS

# =============================================================================
#  CONFIGURATION
# =============================================================================

DATA_DIR        = os.path.expanduser("~/.nomadnetwork/rssidata")
NAMES_FILE      = os.path.join(DATA_DIR, "names.json")
TIMES_FILE      = os.path.join(DATA_DIR, "names_times.json")

# =============================================================================
#  HELPERS
# =============================================================================

def load_json(path):
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_json(path, data):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


# =============================================================================
#  ANNOUNCE HANDLER
# =============================================================================

names = load_json(NAMES_FILE)
times = load_json(TIMES_FILE)


def announce_handler(destination_hash, announced_identity, app_data):
    global names, times
    h   = destination_hash.hex()
    now = int(time.time())

    # ── Update first/last seen timestamps for every announce ─────────────────
    if h in times:
        times[h]["last_seen"] = now
    else:
        times[h] = {"first_seen": now, "last_seen": now}
    save_json(TIMES_FILE, times)

    # ── Update name if app_data is present and has changed ───────────────────
    if app_data:
        try:
            name = app_data.decode("utf-8").strip()
            if name and names.get(h) != name:
                names[h] = name
                save_json(NAMES_FILE, names)
        except Exception:
            pass


# =============================================================================
#  MAIN
# =============================================================================

def main():
    os.makedirs(DATA_DIR, exist_ok=True)

    # Connect to the existing shared rnsd instance (no new transport started)
    RNS.Reticulum()

    class AnnounceHandler:
        def __init__(self):
            self.aspect_filter = None

        def received_announce(self, destination_hash, announced_identity, app_data):
            announce_handler(destination_hash, announced_identity, app_data)

    handler = AnnounceHandler()
    RNS.Transport.register_announce_handler(handler)

    # Run forever
    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
