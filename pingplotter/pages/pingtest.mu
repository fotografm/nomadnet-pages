#!/usr/bin/python3
import subprocess, datetime, re

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

print("`l`Ffd0Interface Ping:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

output = subprocess.getoutput("/home/user/nomadnet-env/bin/rnstatus")

hosts = []
for line in output.split('\n'):
    line = line.strip()
    m = re.match(r'^(BackboneInterface|TCPInterface|UDPInterface)\[(.+)/(.+):(\d+)\]$', line)
    if m:
        iface_type = m.group(1)
        iface_label = m.group(2)
        host = m.group(3)
        port = m.group(4)
        hosts.append((iface_type, iface_label, host, port))

for iface_type, label, host, port in hosts:
    print()
    print(f"`Ffd0{iface_type}: `F0f2{label}`f")
    print(f"  `F888Host:`f    `F0fd{host}:{port}`f")
    try:
        result = subprocess.run(
            ['ping', '-c', '1', '-W', '2', host],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            time_match = re.search(r'time=([\d\.]+)\s*ms', result.stdout)
            if time_match:
                ms = float(time_match.group(1))
                colour = '`F0f2' if ms < 50 else ('`Ffd0' if ms < 150 else '`Ff00')
                print(f"  `F888Ping:`f    {colour}{ms:.1f} ms`f")
            else:
                print(f"  `F888Ping:`f    `Ffd0responded but no time`f")
        else:
            print(f"  `F888Ping:`f    `Ff00no response`f")
    except subprocess.TimeoutExpired:
        print(f"  `F888Ping:`f    `Ff00timeout`f")
    except Exception as e:
        print(f"  `F888Ping:`f    `Ff00error: {e}`f")

print()
print("`F888Note: 'no response' indicates the host blocks ICMP ping packets,`f")
print("`F888      not that the host is down. RNS connectivity may still be active.`f")
print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
