# pingplotter

Nomadnet pages for a TCP-connected Reticulum node with network monitoring and graphing tools.

## Structure

```
pingplotter/
├── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
└── scripts/    # background daemons required by the pages
```

## Pages

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| ping-graph.mu | Live ping RTT graph to selected Reticulum nodes |
| mtr-graph.mu | MTR traceroute graph |
| announces.mu | Reticulum announce monitor |
| announce-rate.mu | Announce rate over time |
| iface-traffic.mu | Interface traffic stats |
| rnpath.mu | Reticulum path lookup |
| rnstatus.mu | Reticulum interface status |
| neofetch.mu | System info via neofetch |
| netio.mu | Network I/O stats |
| pingtest.mu | Simple ping test |
| services.mu | Systemd service status |
| sysinfo.mu | Basic system info |
| sysinfo2.mu | Extended system info |
| uptime.mu | System uptime |
| testpage.mu | Test page |

## Background Daemons

| Script | Required by | Description |
|--------|-------------|-------------|
| announce-listener.py | announce-rate.mu | Listens for RNS announces and logs timestamps to file |

## Dependencies

### Python venv

Pages use `~/.venvs/pingtools/bin/python3` as their shebang interpreter.

```bash
python3 -m venv ~/.venvs/pingtools
~/.venvs/pingtools/bin/pip install plotille typing_extensions
```

### apt packages

```bash
sudo apt install neofetch
```
