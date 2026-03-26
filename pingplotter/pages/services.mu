#!/usr/bin/python3
import subprocess, datetime

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

print("`l`Ffd0Service Status:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

services = [
    ('rnsd',        'Reticulum Daemon'),
    ('nomadnet',    'Nomad Network'),
    ('meshchat',    'MeshChat'),
    ('lxmfd',       'LXMF Daemon'),
    ('ssh',         'SSH Server'),
]

max_label = max(len(label) for _, label in services)

for service, label in services:
    pad = ' ' * (max_label - len(label))
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', service],
            capture_output=True, text=True
        )
        status = result.stdout.strip()
        if status == 'active':
            colour = '`F0f2'
        elif status == 'inactive':
            colour = '`F888'
        else:
            colour = '`Ff00'
        print(f"  `Ffd0{label}:`f{pad}  {colour}{status}`f")
    except Exception as e:
        print(f"  `Ffd0{label}:`f{pad}  `Ff00error: {e}`f")

print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
