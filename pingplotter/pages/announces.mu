#!/usr/bin/python3
# =============================================================================
#  announces.mu  —  Nomadnet page: announce rates and propagation node log
#  Place in: ~/.nomadnetwork/storage/pages/announces.mu
#
#  How it works:
#    Section 1 — Runs `rnstatus -A` and parses its text output to show the
#                outbound announce rate for every active interface, one block
#                per interface.
#    Section 2 — Scans the Nomadnet logfile for lines matching the propagation
#                node announce pattern and displays the 20 most recent ones in
#                reverse-chronological order (newest first).
#
#  Full paths are required for all RNS binaries.  Nomadnet does not activate
#  a venv when it executes page scripts, so bare command names only resolve
#  against the system PATH.  rnstatus lives inside ~/nomadnet-env alongside
#  nomadnet itself.
#
#  Colour palette:
#    `Ffd0  gold   — section headings / interface labels
#    `F0f2  green  — dividers / Up status / announce counts
#    `Ff00  red    — Down status / errors
#    `F0fd  cyan   — interface name text / destination hashes
#    `F888  grey   — secondary / dim labels and timestamps
# =============================================================================

import subprocess
import datetime
import re
import os

# Full path to rnstatus inside the nomadnet venv — required because Nomadnet
# does not activate any venv when it runs page scripts.
RNSTATUS = '/home/user/nomadnet-env/bin/rnstatus'

# Nomadnet writes all log output to this file when running as a service.
LOGFILE = os.path.expanduser('~/.nomadnetwork/logfile')

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

# Micron page header — c=0 must be the very first line so Nomadnet re-executes
# the script on every visit rather than serving a cached copy.
print("#!c=0")
print("`l`Ffd0Recent Announces:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# =============================================================================
#  Section 1 — Announce rates per interface (from rnstatus -A)
# =============================================================================
# rnstatus -A adds announce rate lines to the standard interface status output.
# The relevant part of each interface block looks like:
#
#   TCPInterface[MyPeer/1.2.3.4:4242]
#      Status  : Up
#      ...
#      Announces: 12/s   ← outbound announce rate (the line we want)
#                 3/s    ← inbound rate on a continuation line (we skip this)
#
# We walk the output line by line, tracking the current interface, and emit
# one summary line per interface once we have both status and announce rate.

try:
    output = subprocess.check_output(
        [RNSTATUS, '-A'],
        stderr=subprocess.STDOUT
    ).decode('utf-8').strip()

    print("`Ffd0Announce rates by interface:`f")
    print()

    # State for the current interface block being parsed.
    iface_name          = None
    iface_type          = None
    status              = None
    announces_up        = None
    skip_next_announces = False  # flag to ignore the inbound rate continuation line

    for line in output.split('\n'):
        line = line.strip()
        if not line or '---' in line:
            continue

        # Interface header line — starts a new block.
        # Examples:
        #   TCPInterface[MyPeer/1.2.3.4:4242]
        #   AutoInterfacePeer[ens18/fe80::1]
        #   SharedInstance[37428]
        iface_match = re.match(
            r'^(SharedInstance|Shared Instance|BackboneInterface|'
            r'AutoInterface|AutoInterfacePeer|TCPInterface|UDPInterface)\[(.+)\]$',
            line
        )
        if iface_match:
            # Flush the previous interface block before starting the next one.
            if iface_name and announces_up:
                status_colour = '`F0f2' if status == 'Up' else '`Ff00'
                print(f"  `Ffd0{iface_type}: `F0fd{iface_name}`f")
                print(f"    `F888Status:`f {status_colour}{status}`f  `F888Announces↑:`f `F0f2{announces_up}`f")

            iface_type          = iface_match.group(1)
            iface_name          = iface_match.group(2)
            status              = None
            announces_up        = None
            skip_next_announces = False
            continue

        if line.startswith('Status'):
            status = line.split(':', 1)[1].strip()

        elif line.startswith('Announces'):
            if not skip_next_announces:
                # First Announces line is the outbound (↑) rate.
                announces_up        = line.split(':', 1)[1].strip()
                skip_next_announces = True  # next bare numeric line is ↓ rate

        elif skip_next_announces and re.match(r'^[\d\.]+', line):
            # This is the inbound rate continuation — consume and move on.
            skip_next_announces = False

    # Flush the final interface block after the loop ends.
    if iface_name and announces_up:
        status_colour = '`F0f2' if status == 'Up' else '`Ff00'
        print(f"  `Ffd0{iface_type}: `F0fd{iface_name}`f")
        print(f"    `F888Status:`f {status_colour}{status}`f  `F888Announces↑:`f `F0f2{announces_up}`f")

except Exception as e:
    print(f"`Ff00rnstatus error: {e}`f")

# =============================================================================
#  Section 2 — Recent propagation node announces (from Nomadnet logfile)
# =============================================================================
# Nomadnet logs a line like:
#   [2026-02-27 12:00:00] [Notice]  Received active propagation node announce from <abc123>
# whenever a propagation node sends an announce.  We scan the entire logfile,
# collect all matching lines, and display the 20 most recent in reverse order.

print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`Ffd0Last 20 propagation node announces:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

try:
    with open(LOGFILE, 'r') as f:
        lines = f.readlines()

    announces = []
    for line in lines:
        m = re.match(
            r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[\w+\]\s+'
            r'Received active propagation node announce from <([0-9a-f]+)>',
            line
        )
        if m:
            announces.append((m.group(1), m.group(2)))

    # Take the last 20 entries and display newest first.
    recent = announces[-20:]
    if recent:
        for ts, h in reversed(recent):
            print(f"`F888{ts}`f  `F0fd{h}`f")
    else:
        print("`Ff00No propagation node announces found in log`f")

except FileNotFoundError:
    print(f"`Ff00Logfile not found: {LOGFILE}`f")
except Exception as e:
    print(f"`Ff00Error reading logfile: {e}`f")

print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
