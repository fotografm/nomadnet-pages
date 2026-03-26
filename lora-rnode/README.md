# lora-rnode

Nomadnet pages for a Reticulum node connected via LoRa radio only (RNode interface).
No TCP interfaces are configured on this server — all traffic is over LoRa.

## Structure

```
lora-rnode/
├── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
└── scripts/    # background daemons required by the pages
```

## Pages

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

## Background Daemons

These scripts must be running for the graph pages to have data.
Deploy them to `~/` on the server and start them as systemd services or in tmux.

| Script | Required by | Description |
|--------|-------------|-------------|
| noise-logger.py | noise-monitor-braille.mu, rf-noise.mu | Polls rnstatus and logs RF noise floor and channel load to JSON |
| rssi-logger.py | rssi-monitor.mu, rf-rssi.mu | Listens for RNS announces and logs RSSI/SNR per node to JSON |
| names-resolver.py | names.mu, rssi-monitor.mu | Resolves RNS destination hashes to human-readable app_data names |

## Dependencies

### Python venv

Pages use `~/.venvs/rns-tools/bin/python3` as their shebang interpreter.

```bash
python3 -m venv ~/.venvs/rns-tools
~/.venvs/rns-tools/bin/pip install plotille typing_extensions rns
```

### No apt dependencies required

All functionality is handled by the venv and the RNS stack.

## Notes

- Pages are served by a running Nomadnet node
- The LoRa interface runs at 869.525 MHz via an RNode device on /dev/ttyUSB0
- Bandwidth is limited — pages are designed to minimise transmitted characters
- noise-monitor-braille.mu uses plain ASCII * rendering (no Unicode braille) to reduce page size over the air
