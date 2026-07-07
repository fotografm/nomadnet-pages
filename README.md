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

## Server setup & reliability

Notes on running `nomadnet` itself as an always-on systemd service, distilled from
comparing the `pingplotter` and webcam (`ascii-webcam`/`jpeg-webcam`) servers and
fixing the startup-reliability issues found on each.

### Architecture: embedded vs. shared `rnsd`

Reticulum can run two ways, pick one per server:

- **Embedded** (`pingplotter`): `nomadnet` starts its own Reticulum instance
  directly. Simplest option if nomadnet is the only Reticulum-using process on
  the box.
- **Shared instance via `rnsd`** (webcam server): a separate `rnsd.service` owns
  the actual interfaces and Reticulum Transport; `nomadnet` and any companion
  daemon connect to it as clients over a local Unix domain socket. Needed when
  more than one local app requires Reticulum. This is the default behavior when
  `share_instance = Yes` in `~/.reticulum/config` (the default) — whichever
  process starts first becomes the shared instance.

Either way, `nomadnet` lives in a venv, conventionally at `~/nomadnet-env/`:
```
python3 -m venv ~/nomadnet-env
~/nomadnet-env/bin/pip install rns nomadnet
```

### Running the TUI headless: tmux

`nomadnet` with no arguments is a full-screen TUI — it needs a real pty, so it
can't run as a plain systemd service with no terminal. The pattern is to have
systemd launch it detached inside `tmux`, so you can attach to the same running
session later:
```
tmux attach -t nomadnet
```
(Detach without killing it: `Ctrl-b` then `d`.) **Use the default tmux socket**,
not a custom `-L` socket — a custom socket means remembering to pass `-L <name>`
on every attach, and forgetting it produces a confusing "no sessions" error
against the wrong (default) socket for no benefit.

### systemd units

`rnsd.service` (shared-instance architecture only):
```ini
[Unit]
Description=Reticulum Network Stack Daemon
After=network.target

[Service]
Type=simple
User=user
ExecStart=/home/user/nomadnet-env/bin/rnsd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
Note `Type=simple` means systemd considers this "started" the instant the
process forks — not when Reticulum Transport is actually ready. That matters for
`nomadnet.service` below.

`nomadnet.service` — the reliable version:
```ini
[Unit]
Description=Nomadnet
# Shared-instance architecture only:
After=network.target rnsd.service
Requires=rnsd.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=forking
User=user
# Shared-instance architecture: fast-path gate on rnsd's socket existing.
# Embedded architecture: use `ExecStartPre=/bin/sleep 10` instead (just letting
# the network/system settle after boot — there's no companion socket to poll).
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do ss -xl 2>/dev/null | grep -q "@rns/default" && exit 0; sleep 0.5; done'
ExecStart=/usr/bin/tmux new-session -d -s nomadnet '/home/user/nomadnet-env/bin/nomadnet'
ExecStop=-/usr/bin/tmux kill-session -t nomadnet
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Why each piece matters, found by actually reproducing the failures with real VM
reboots (not just `systemctl restart`):

- **`ExecStop=-...`** (leading `-`): if the tmux session already died for any
  reason, the stop command exits nonzero; without the `-` that gets logged as a
  hard failure for what's really a no-op.
- **`Restart=always`, not `Restart=on-failure`, plus a widened
  `StartLimitBurst`**: on the shared-instance server, `nomadnet` occasionally
  exits cleanly (`status=0`) very shortly after systemd launches it — even
  *after* `rnsd`'s shared-instance socket is confirmed already listening. Timing
  tests showed this is genuinely non-deterministic (sometimes fails within 10s
  of an `rnsd` restart, sometimes succeeds within 7s), and it isn't a tmux-state
  or environment issue either — it looks like an occasional hiccup in the RNS
  shared-instance handshake itself (`rnsd`'s own log separately shows an
  unrelated, self-recovering `RuntimeError: dictionary changed size during
  iteration` inside `RNS/Transport.py`, suggesting some thread-safety fragility
  in the underlying library around connection churn). Because the failure is a
  *clean* exit, `Restart=on-failure` does not retry it — the service just sits
  dead until someone notices. `Restart=always` means systemd just tries again a
  few seconds later regardless of exit code, and it reliably succeeds on the
  next attempt. The widened `StartLimitBurst`/`StartLimitIntervalSec` stop a run
  of quick retries during boot from permanently locking the unit into
  `start-limit-hit`.

### Passwordless sudo for `systemctl` (optional, for remote administration)

Scope it — never grant blanket passwordless sudo:
```
# /etc/sudoers.d/systemctl-nopasswd
user ALL=(root) NOPASSWD: /usr/bin/systemctl
```
Always validate *before* installing (a bad sudoers file can lock out all sudo
access):
```
visudo -cf /etc/sudoers.d/systemctl-nopasswd
chown root:root /etc/sudoers.d/systemctl-nopasswd
chmod 0440 /etc/sudoers.d/systemctl-nopasswd
visudo -c
```
Note this doesn't cover `journalctl` (different binary — add it too if wanted),
and `systemctl edit <anything>` opens an editor as root, so this is a
convenience grant, not a hard security boundary.

### New-install checklist

1. Create the venv, install `rns`/`nomadnet`.
2. Pick embedded vs. shared-instance architecture.
3. Install the unit(s) above — default tmux socket, `Restart=always`, widened
   start-limit, tolerant `ExecStop`.
4. `systemctl daemon-reload && systemctl enable --now nomadnet` (and `rnsd`
   first, if applicable).
5. **Test with a real reboot**, not just `systemctl restart` — then
   `journalctl -u nomadnet -b` (and `-u rnsd -b`) to confirm a clean start, or
   at least a successful auto-retry.
6. Confirm `tmux attach -t nomadnet` reaches the running session.

## Licence

MIT — see [LICENSE](LICENSE)
