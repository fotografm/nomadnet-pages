#!/home/user/nomadnet-env/bin/python3
# =============================================================================
#  announce-listener.py  —  Persistent Reticulum announce logger
#
#  Run once after nomadnet is started:
#      ~/.nomadnetwork/announce-listener.py &
#
#  Connects to the existing shared RNS instance and logs every announce
#  received to:
#      ~/.nomadnetwork/announce.log
#
#  Log format (one line per announce):
#      2026-02-25 18:03:42 a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
#
#  Kill with:
#      pkill -f announce-listener.py
# =============================================================================

import RNS
import time
import datetime
import os
import signal
import sys

LOG_FILE   = os.path.expanduser("~/.nomadnetwork/announce.log")
CONFIG_DIR = os.path.expanduser("~/.reticulum")

# Maximum log file size before rotation (10 MB)
MAX_LOG_BYTES = 10 * 1024 * 1024


def rotate_log_if_needed():
    if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > MAX_LOG_BYTES:
        rotated = LOG_FILE + ".1"
        if os.path.exists(rotated):
            os.remove(rotated)
        os.rename(LOG_FILE, rotated)


def write_announce(destination_hash, app_data):
    rotate_log_if_needed()
    now_str  = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hash_hex = RNS.prettyhexrep(destination_hash).replace("<","").replace(">","").replace(":","").lower()

    # app_data is raw bytes — decode safely if present
    app_str = ""
    if app_data:
        try:
            app_str = " " + app_data.decode("utf-8", errors="replace").strip()[:80]
        except Exception:
            pass

    line = f"{now_str} {hash_hex}{app_str}\n"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception as e:
        print(f"[announce-listener] Failed to write log: {e}", flush=True)


class AnnounceHandler:
    """
    Registered with RNS.Transport to receive all announces.
    aspect_filter = None means we receive everything.
    Official RNS signature: received_announce(destination_hash, announced_identity, app_data)
    """
    aspect_filter = None

    def received_announce(self, destination_hash, announced_identity, app_data):
        try:
            write_announce(destination_hash, app_data)
        except Exception as e:
            print(f"[announce-listener] Handler error: {e}", flush=True)


def shutdown(signum, frame):
    print("[announce-listener] Shutting down.", flush=True)
    sys.exit(0)


def main():
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT,  shutdown)

    print("[announce-listener] Starting — connecting to shared RNS instance...", flush=True)

    RNS.Reticulum(configdir=CONFIG_DIR, loglevel=RNS.LOG_WARNING)

    handler = AnnounceHandler()
    RNS.Transport.register_announce_handler(handler)

    print(f"[announce-listener] Listening — logging to {LOG_FILE}", flush=True)

    while True:
        time.sleep(10)


if __name__ == "__main__":
    main()
