#!/usr/bin/python3
import psutil, datetime

now_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

def fmt_bytes(b):
    if b >= 1024**3:
        return f"{b/1024**3:.2f} GB"
    elif b >= 1024**2:
        return f"{b/1024**2:.2f} MB"
    elif b >= 1024:
        return f"{b/1024:.2f} KB"
    else:
        return f"{b} B"

def fmt_speed(bps):
    if bps >= 1024**2:
        return f"{bps/1024**2:.2f} MB/s"
    elif bps >= 1024:
        return f"{bps/1024:.2f} KB/s"
    else:
        return f"{bps:.0f} B/s"

print("`l`Ffd0Network I/O:`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"`Ffd0Time:`f      `F0f2{now_str}")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# Sample twice 1 second apart to get live throughput
import time
counters_before = psutil.net_io_counters(pernic=True)
time.sleep(1)
counters_after = psutil.net_io_counters(pernic=True)

stats = psutil.net_if_stats()

for iface, after in counters_after.items():
    if iface == 'lo':
        continue
    before = counters_before.get(iface)
    if not before:
        continue
    st = stats.get(iface)
    is_up = st.isup if st else False
    if not is_up:
        continue

    sent_total = after.bytes_sent
    recv_total = after.bytes_recv
    sent_speed = after.bytes_sent - before.bytes_sent
    recv_speed = after.bytes_recv - before.bytes_recv
    errors_in = after.errin
    errors_out = after.errout
    drops_in = after.dropin
    drops_out = after.dropout

    print()
    print(f"`Ffd0Interface: `F0f2{iface}`f")
    print(f"  `F888Sent:`f       `F0fd{fmt_bytes(sent_total)}`f  `F888@ `F0f2{fmt_speed(sent_speed)}`f")
    print(f"  `F888Received:`f   `F0fd{fmt_bytes(recv_total)}`f  `F888@ `F0f2{fmt_speed(recv_speed)}`f")

    err_colour = '`Ff00' if (errors_in + errors_out) > 0 else '`F0f2'
    drop_colour = '`Ff00' if (drops_in + drops_out) > 0 else '`F0f2'
    print(f"  `F888Errors:`f     {err_colour}in={errors_in} out={errors_out}`f")
    print(f"  `F888Drops:`f      {drop_colour}in={drops_in} out={drops_out}`f")

print()
print("`F888Note: throughput is sampled over 1 second`f")
print()
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`a")
