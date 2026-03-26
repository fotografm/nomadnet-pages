#!/usr/bin/python3

import subprocess
print(f"The hostname is: ")
print(subprocess.check_output(['hostname']).decode('utf-8').strip())
print()

print(f"Operating System: ")
print(subprocess.check_output(['cat', '/etc/os-release']).decode('utf-8').split('PRETTY_NAME=')[1].strip().replace('"', ''))
print()

print(f"Used Memory: ")
print(subprocess.check_output(['free', '-h']).decode('utf-8').split('Mem:')[1].split()[1])
print()

print(f"Disk Space:     Total Used  Free  Usage")
output = subprocess.check_output(['df', '-h']).decode('utf-8').split('\n')
for line in output:
    if '/dev/' in line:
        print(line)
print()

print(f"Reticulum Version: ")
print(subprocess.check_output(['rnsd',  '--version']).decode('utf-8').strip())
print()
