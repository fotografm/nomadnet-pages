# nomadnet-pages

A collection of [Nomadnet](https://github.com/markqvist/NomadNet) `.mu` pages and supporting Python scripts, organised by server.

## Structure

```
nomadnet-pages/
├── pingplotter/
│   ├── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
│   └── scripts/    # .py dependencies called by the .mu pages
├── ascii-webcam/
│   └── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
├── lora-rnode/
│   ├── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
│   └── scripts/    # background daemons required by the pages
└── jpeg-webcam/
    └── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
```

Each subdirectory is a self-contained Nomadnet server. Pages and scripts for one server are never mixed with another.

## Pages — pingplotter

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

**Dependencies:** `~/.venvs/pingtools/` venv with `plotille` and `typing_extensions`. `announce-listener.py` daemon must be running for announce-rate.mu.

## Pages — ascii-webcam

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| webcam.mu | Live webcam image rendered as ASCII art |
| webcam-colour.mu | Live webcam image as thermal-style colour ASCII art |

**Dependencies:** `fswebcam` (`sudo apt install fswebcam`), `Pillow` in `~/nomadnet-env`. User must be in the `video` group.

## Pages — lora-rnode

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| sysinfo.mu | Basic system info |
| sysinfo2.mu | Extended system info |
| rnstatus.mu | Reticulum interface status |
| retconfig.mu | Displays ~/.reticulum/config content |
| noise-monitor-braille.mu | RF noise floor and channel load graphs over time |
| rf-noise.mu | Live RF noise floor reading |
| rf-rssi.mu | Live RSSI from most recent LoRa packet |
| rssi-monitor.mu | Per-node RSSI/SNR from announces, plotted over time |
| names.mu | Lists known nodes with resolved human-readable names |

**Dependencies:** `~/.venvs/rns-tools/` venv with `plotille`, `typing_extensions` and `rns`. Daemons `noise-logger.py`, `rssi-logger.py` and `names-resolver.py` must be running for graph and names pages.

## Pages — jpeg-webcam

| Page | Description |
|------|-------------|
| index.mu | Landing page with links to live webcam JPEG files |
| status.mu | Reticulum interface status via rnstatus |
| sysinfo.mu | Basic system info |

**Dependencies:** `fswebcam` (`sudo apt install fswebcam`). User must be in the `video` group. A cron job writes JPEGs every 2 minutes to `~/.nomadnetwork/storage/files/` for Nomadnet to serve via `/file/` links.

## Licence

MIT — see [LICENSE](LICENSE)
