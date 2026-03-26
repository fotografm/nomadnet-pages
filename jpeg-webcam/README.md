# jpeg-webcam

Nomadnet pages for a Reticulum node that serves live webcam images as downloadable
JPEG files via Nomadnet's built-in file serving. No ASCII conversion — clients
receive the actual JPEG files directly.

## Structure

```
jpeg-webcam/
└── pages/      # .mu pages → deploy to ~/.nomadnetwork/storage/pages/
```

Files are written directly to `~/.nomadnetwork/storage/files/` by a cron job
and served via `/file/` links in the index page.

## Pages

| Page | Description |
|------|-------------|
| index.mu | Landing page with links to live webcam images and status pages |
| status.mu | Reticulum interface status via rnstatus |
| sysinfo.mu | Basic system info — hostname, OS, memory, disk, RNS version |

## How It Works

A cron job runs `fswebcam` every 2 minutes and writes the captured JPEG directly
to `~/.nomadnetwork/storage/files/`. Nomadnet serves any file in that directory
via a `/file/filename` path, which clients can request and download.

The index page links to the images using Micron file links:

```
`F0FD`[Image description`:/file/image.jpg`]`f
```

## Dependencies

### apt packages

```bash
sudo apt install fswebcam
```

### Cron job

Add to crontab (`crontab -e`):

```
*/2 * * * * /usr/bin/fswebcam -d v4l2:/dev/video0 -r 320x240 --jpeg 50 -D 5 ~/.nomadnetwork/storage/files/image.jpg
```

The `-D 5` flag adds a 5-second delay before capture to allow the camera to
adjust exposure. Adjust `-r 320x240` for your preferred resolution and
`--jpeg 50` for JPEG quality (0-100).

### Video group membership

```bash
sudo usermod -aG video user
```

A reboot is required after adding the user to the group.

## Notes

- Files in `~/.nomadnetwork/storage/files/` are overwritten on each capture
- Multiple camera angles can be served by adding more cron entries writing
  to different filenames (image.jpg, image2.jpg, image3.jpg etc.)
- Nomadnet must have `enable_node = yes` in its config for file serving to work
