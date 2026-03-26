#!/usr/bin/env python3
import os
config_path = os.path.expanduser("~/.reticulum/config")
print("#!c=0")
print("`l`Ffff> Reticulum Config`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`f")
print("")
print("`=")
try:
    with open(config_path, "r") as f:
        for line in f:
            print(line.rstrip())
except FileNotFoundError:
    print("`=")
    print("`F880Config file not found: " + config_path + "`f")
except PermissionError:
    print("`=")
    print("`F880Permission denied reading: " + config_path + "`f")
else:
    print("`=")
print("")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`f")
