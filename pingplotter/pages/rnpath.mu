#!/usr/bin/python3
# =============================================================================
#  rnpath.mu  —  Nomadnet page: Reticulum path table summary
#  Place in: ~/.nomadnetwork/storage/pages/rnpath.mu
#
#  How it works:
#    Runs `rnpath -t -j` on every page load (c=0) to get the full path table
#    as JSON, then summarises it as:
#      - Total known paths
#      - Hop count breakdown with colour coding
#      - Direct neighbours (1-hop peers) with their interface names
#
#  Requires: rnpath at /home/user/nomadnet-env/bin/rnpath (inside nomadnet-env venv)
#
#  Colour palette:
#    `Ffd0  gold   — headings / labels
#    `F0f2  green  — dividers / 1-2 hop paths
#    `Ffd0  gold   — 3-4 hop paths
#    `Ff00  red    — 5+ hop paths / errors
#    `F0fd  cyan   — hash values / counts
#    `F888  grey   — secondary labels
#
#  Why JSON mode (-j) instead of text parsing:
#    Earlier versions of this script used `rnpath -t` (plain text) and parsed
#    it with a regex anchored on the word "expires".  RNS 1.x changed the
#    text output format and removed that token, so the regex matched nothing
#    and the page went blank after the header.  Switching to -j gives us a
#    stable, version-independent data structure to work with.
# =============================================================================

import subprocess
import datetime
import json
from collections import defaultdict

# Timestamp shown at the top of every page load.
now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

# Micron page header — c=0 must be the very first line printed so Nomadnet
# re-executes the script on every visit rather than serving a cached copy.
print("#!c=0")
print("`l`Ffd0RNS Path Summary:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

try:
    # -t  : dump full path table (all known destinations)
    # -j  : output as JSON instead of human-readable text
    # Using JSON avoids brittle text-format parsing that breaks across RNS
    # versions (the old regex relied on the word "expires" which was removed).
    #
    # Full path is required — Nomadnet does not activate a venv when it runs
    # page scripts, so bare command names only resolve against the system PATH.
    # rnpath lives inside ~/nomadnet-env alongside nomadnet itself.
    RNPATH = '/home/user/nomadnet-env/bin/rnpath'

    raw = subprocess.check_output(
        [RNPATH, '-t', '-j'],
        stderr=subprocess.STDOUT
    ).decode('utf-8').strip()

    # rnpath -t -j emits a JSON object whose keys are destination hashes and
    # whose values are dicts with at least:
    #   "hops"      : int   — number of hops to reach the destination
    #   "interface" : str   — name of the local interface used to reach it
    #   "expires"   : float — Unix timestamp when the path record expires
    #                         (may be absent on some builds, so we default it)
    # rnpath -t -j (RNS 1.1.3+) returns a JSON array of path objects.
    # Each object has the fields: hash, timestamp, via, hops, expires, interface.
    paths = json.loads(raw)

    # Aggregate hop counts and collect direct (1-hop) neighbours.
    hop_counts        = defaultdict(int)
    direct_neighbours = []

    for entry in paths:
        dest_hash = entry.get('hash', 'unknown')
        hops      = int(entry.get('hops', 0))
        iface     = entry.get('interface', 'unknown')

        hop_counts[hops] += 1

        if hops == 1:
            direct_neighbours.append((dest_hash, iface))

    total = sum(hop_counts.values())

    print(f"`Ffd0Total paths:`f  `F0f2{total}`f")
    print()
    print("`Ffd0Hop breakdown:`f")

    for h in sorted(hop_counts.keys()):
        # Colour-code by hop distance: green = close, gold = medium, red = far.
        if h <= 2:
            hop_colour = '`F0f2'
        elif h <= 4:
            hop_colour = '`Ffd0'
        else:
            hop_colour = '`Ff00'

        hop_label = 'hop' if h == 1 else 'hops'
        print(f"  {hop_colour}{h} {hop_label}:`f  `F0fd{hop_counts[h]}`f")

    print()
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"`Ffd0Direct neighbours (1 hop): `F0f2{len(direct_neighbours)}`f")
    print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    if direct_neighbours:
        for dest, iface in direct_neighbours:
            # Interface names from the JSON look like:
            #   "TCPClientInterface[MyPeer/192.0.2.1:4242]"
            # Split on '[' to separate the type from the bracketed name portion.
            iface_parts = iface.split('[', 1)
            iface_type  = iface_parts[0]
            iface_name  = iface_parts[1].rstrip(']') if len(iface_parts) > 1 else ''

            print(f"`F0fd{dest}`f  `Ffd0{iface_type}:`f `F0f2{iface_name}`f")
    else:
        print("`Ff00No direct neighbours found`f")

except subprocess.CalledProcessError as e:
    # rnpath itself returned a non-zero exit code — show whatever it printed.
    print(f"`Ff00Error running rnpath: {e.output.decode('utf-8').strip()}`f")

except json.JSONDecodeError as e:
    # rnpath ran but its output was not valid JSON.  This can happen if an
    # older RNS version that predates the -j flag is installed, or if rnpath
    # printed a warning/notice before the JSON block.
    print(f"`Ff00JSON parse error — is RNS >= 1.0 installed?`f")
    print(f"`F888{e}`f")

except FileNotFoundError:
    # The rnpath binary was not found at the expected venv path.
    print("`Ff00rnpath not found — check /home/user/nomadnet-env/bin/rnpath exists`f")

print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
