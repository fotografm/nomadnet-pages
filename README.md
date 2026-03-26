# nomadnet-pages

A collection of [Nomadnet](https://github.com/markqvist/NomadNet) `.mu` pages and supporting Python scripts, organised by server.

## Structure

```
nomadnet-pages/
├── pingplotter/
│   ├── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
│   └── scripts/    # .py dependencies called by the .mu pages
└── ascii-webcam/
    └── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
```

Each subdirectory is a self-contained Nomadnet server. Pages and scripts for one server are never mixed with another.

## Pages — pingplotter

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| ping-graph.mu | Live ping graph to selected hosts |
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

## Pages — ascii-webcam

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| webcam.mu | Live webcam image in ASCII art |
| webcam-colour.mu | Live webcam image in colour ASCII art |

## Dependencies

Pages are served by a running Nomadnet node. Scripts (where present) require the same Python venv as Nomadnet (`~/nomadnet-env`).

## Licence

MIT — see [LICENSE](LICENSE)
