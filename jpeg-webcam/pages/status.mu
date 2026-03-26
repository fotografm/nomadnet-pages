#!/usr/bin/python3
import subprocess

rnstatus = subprocess.getoutput("/home/user/.local/bin/rnstatus")

print(rnstatus)
