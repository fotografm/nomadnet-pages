# ascii-webcam

Nomadnet pages for a Reticulum node with a live webcam rendered as ASCII art.

## Structure

```
ascii-webcam/
└── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
```

No background daemons required — pages capture the webcam on each page load.

## Pages

| Page | Description |
|------|-------------|
| index.mu | Landing page |
| webcam.mu | Live webcam image rendered as ASCII art |
| webcam-colour.mu | Live webcam image as thermal-style colour ASCII art |

## Dependencies

### apt packages

```bash
sudo apt install fswebcam
```

### Python venv

Pages use `~/nomadnet-env/bin/python3` as their shebang interpreter.

```bash
python3 -m venv ~/nomadnet-env
~/nomadnet-env/bin/pip install Pillow
```

### Video group membership

The user running Nomadnet must be in the `video` group, otherwise fswebcam cannot access the camera device:

```bash
sudo usermod -aG video user
```

A reboot is required after adding the user to the group.
