#!/usr/bin/python3
import os, json, datetime

DATA_DIR        = os.path.expanduser("~/.nomadnetwork/rssidata")
NAMES_FILE      = os.path.join(DATA_DIR, "names.json")
TIMES_FILE      = os.path.join(DATA_DIR, "names_times.json")

now_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

SEP  = "`F0f2" + "━" * 95 + "`f"
SEP2 = "`F888" + "─" * 95 + "`f"

def fmt_dt(epoch):
    return datetime.datetime.utcfromtimestamp(epoch).strftime("%Y-%m-%d %H:%M")

print("`Ffd0Known Node Names — all times in UTC`f")
print(SEP)
print(f"`F888Updated:`f `Ffd0{now_str}`f")
print(SEP)

if not os.path.exists(NAMES_FILE):
    print("`F550No names.json yet — waiting for announces.`f")
else:
    try:
        with open(NAMES_FILE) as f:
            names = json.load(f)

        # Load names_times.json as fallback for nodes without RSSI data files
        times = {}
        if os.path.exists(TIMES_FILE):
            try:
                with open(TIMES_FILE) as f:
                    times = json.load(f)
            except Exception:
                pass

        if not names:
            print("`F550No names recorded yet.`f")
        else:
            print(f"`F888Total nodes: `F0f2{len(names)}`f")
            print(SEP)

            W_HASH  = 16
            W_FIRST = 16
            W_LAST  = 16

            h_hash  = "Hash".ljust(W_HASH)
            h_first = "First seen (UTC)".ljust(W_FIRST)
            h_last  = "Last seen (UTC)".ljust(W_LAST)
            print(f"`F888{h_hash}  {h_first}  {h_last}  Name`f")
            print(SEP2)

            for h, name in sorted(names.items(), key=lambda x: x[1].lower()):
                first_txt = "unknown         "
                last_txt  = "unknown         "

                # Prefer RSSI data file (1-hop radio nodes — most accurate)
                data_file = os.path.join(DATA_DIR, h + ".json")
                if os.path.exists(data_file):
                    try:
                        with open(data_file) as df:
                            samples = json.load(df)
                        if samples:
                            first_txt = fmt_dt(samples[0]['t'])
                            last_txt  = fmt_dt(samples[-1]['t'])
                    except Exception:
                        pass
                # Fall back to names_times.json for local/multi-hop nodes
                elif h in times:
                    first_txt = fmt_dt(times[h]["first_seen"])
                    last_txt  = fmt_dt(times[h]["last_seen"])

                first_colored = f"`F0fd{first_txt:<{W_FIRST}}`f"
                last_colored  = f"`F0fd{last_txt:<{W_LAST}}`f"
                hash_colored  = f"`F0fd{h[:W_HASH]}`f"
                name_colored  = f"`Ffd0{name}`f"

                print(f"{hash_colored}  {first_colored}  {last_colored}  {name_colored}")

    except Exception as e:
        print(f"`F500Error reading names.json: {e}`f")

print(SEP)
