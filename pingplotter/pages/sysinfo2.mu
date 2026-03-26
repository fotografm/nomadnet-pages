#!/usr/bin/python3
import subprocess, datetime

def run(cmd):
    return subprocess.check_output(cmd).decode('utf-8').strip()

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

print("`l`Ffd0System Info:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f       `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

print(f"`Ffd0Hostname:`f  `F0fd{run(['hostname'])}`f")

os_name = run(['cat', '/etc/os-release'])
os_name = os_name.split('PRETTY_NAME=')[1].split('\n')[0].replace('"', '')
print(f"`Ffd0OS:`f        `F0fd{os_name}`f")

mem = run(['free', '-h']).split('Mem:')[1].split()
print(f"`Ffd0Memory:`f    `F0fd{mem[1]} / {mem[0]} used`f")

print()
print("`Ffd0Disk:`f")
df_output = run(['df', '-h']).split('\n')
for line in df_output:
    if '/dev/' in line:
        parts = line.split()
        print(f"  `F0fd{parts[5]}`f  {parts[1]} total  `F0f2{parts[3]}`f free  `Ffd0{parts[4]}`f used")

print()
rns_ver = run(['rnsd', '--version'])
print(f"`Ffd0Reticulum:`f `F0f2{rns_ver}`f")
print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
