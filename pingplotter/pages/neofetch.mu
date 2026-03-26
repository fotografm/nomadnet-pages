#!/usr/bin/python3
import subprocess, datetime

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

print("`l`Ffd0System Info (neofetch):`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

output = subprocess.check_output(["neofetch", "--stdout"]).decode("utf-8")

# First pass — collect all label/value pairs to find max label length
rows = []
for line in output.split('\n'):
    line = line.strip()
    if not line:
        continue
    if ':' in line:
        parts = line.split(':', 1)
        rows.append(('kv', parts[0].strip(), parts[1].strip()))
    elif '@' in line:
        parts = line.split('@', 1)
        rows.append(('at', parts[0].strip(), parts[1].strip()))
    elif set(line) == {'-'}:
        rows.append(('sep', '', ''))
    else:
        rows.append(('other', '', line))

max_len = max((len(r[1]) for r in rows if r[0] == 'kv'), default=10)

# Second pass — print with aligned values
for kind, a, b in rows:
    if kind == 'kv':
        pad = ' ' * (max_len - len(a))
        print(f"`Ffd0{a}:`f{pad}  `F0fd{b}`f")
    elif kind == 'at':
        print(f"`F0f2{a}`F888@`F0fd{b}`f")
    elif kind == 'sep':
        print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    else:
        print(f"`F888{b}`f")

print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
