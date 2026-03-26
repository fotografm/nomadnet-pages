#!/usr/bin/python3
import psutil, datetime, os

def hrs(seconds):
    d = int(seconds // 86400)
    h = int((seconds % 86400) // 3600)
    m = int((seconds % 3600) // 60)
    return f"{d}d {h}h {m}m"

boot = psutil.boot_time()
uptime_sec = (datetime.datetime.now() - datetime.datetime.fromtimestamp(boot)).total_seconds()
load1, load5, load15 = os.getloadavg()
boot_str = datetime.datetime.fromtimestamp(boot).strftime('%Y-%m-%d %H:%M:%S')
now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

print("`l`Ffd0Node Uptime:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print(f"`Ffd0Boot:`f      `F0fd{boot_str}")
print(f"`Ffd0Uptime:`f    `F0f2{hrs(uptime_sec)}")
print(f"`Ffd0Load 1m:`f   `F0fd{load1:.2f}")
print(f"`Ffd0Load 5m:`f   `F0fd{load5:.2f}")
print(f"`Ffd0Load 15m:`f  `F0fd{load15:.2f}")
print("`a")
