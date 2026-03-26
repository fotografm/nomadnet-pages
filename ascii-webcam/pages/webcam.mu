#!/home/user/nomadnet-env/bin/python3
#
# webcam.mu — NomadNet dynamic page: live webcam as ASCII art
#
# This script is executed by NomadNet's node server each time a client
# requests /page/webcam.mu. It captures a still frame from the webcam,
# converts it to ASCII art, and prints valid Micron markup to stdout,
# which NomadNet sends to the client as the page content.
#
# Requirements:
#   - fswebcam installed:  sudo apt install fswebcam
#   - Pillow installed in the venv:  pip install Pillow
#   - This file must be executable:  chmod +x webcam.mu
#   - NomadNet must be restarted (or page_refresh_interval set) after
#     adding this file to the pages directory for it to be registered.
#
# Camera device is passed to fswebcam using the v4l2 driver prefix.
# Adjust CAM_DEVICE if your camera appears on a different /dev/videoN.

import subprocess
import os
import tempfile
from PIL import Image

# --- Configuration ---

# V4L2 device path for the webcam
CAM_DEVICE = "v4l2:/dev/video0"

# Width and height of the ASCII art output in characters.
# 76 wide fits cleanly inside NomadNet's default terminal width.
WIDTH  = 76
HEIGHT = 38

# Character palette mapping dark (index 0) to light (index -1) pixel values.
# Deliberately excludes '-' and '=' which Micron interprets as horizontal rules,
# and '+' which can trigger other formatting. Safe printable ASCII only.
ASCII_CHARS = "@%#*+~;:,. "


# --- Functions ---

def capture(path):
    """
    Capture a single JPEG frame from the webcam using fswebcam.

    -S 5 skips the first 5 frames, which are typically overexposed
    while the camera sensor is warming up. This is the main reason
    early captures look washed out.

    capture_output=True suppresses fswebcam's stderr chatter.
    timeout=20 is a Python-level safety net — if fswebcam hangs for
    any reason (e.g. camera locked by another process), the subprocess
    is killed after 20 seconds rather than blocking NomadNet indefinitely.

    Returns True only if fswebcam exited cleanly AND wrote a non-empty file.
    """
    result = subprocess.run(
        ["/usr/bin/fswebcam",
         "-d", CAM_DEVICE,
         "-r", "320x240",       # Capture resolution — low res is fine for ASCII
         "--jpeg", "50",         # JPEG quality 50 — sufficient for greyscale conversion
         "--no-banner",          # Suppress fswebcam's timestamp/info banner overlay
         "-S", "5",              # Skip first 5 frames for sensor warm-up
         "-q", path],            # Quiet mode — suppress progress output; save to path
        capture_output=True,     # Capture stderr so it doesn't leak into Micron output
        timeout=20               # Python-level timeout in seconds (not an fswebcam flag)
    )
    return result.returncode == 0 and os.path.getsize(path) > 0


def to_ascii(path):
    """
    Convert a JPEG image file to an ASCII art string.

    Steps:
      1. Open the image and convert to greyscale ('L' mode)
      2. Resize to (WIDTH, HEIGHT) using Lanczos resampling
      3. Map each pixel value (0-255) to a character in ASCII_CHARS
      4. Assemble into rows of WIDTH characters

    Each line is clamped to WIDTH with [:WIDTH] to prevent any
    off-by-one from producing lines that overflow the terminal and
    wrap undesirably in the Micron renderer.
    """
    img = Image.open(path).convert("L")
    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
    px  = list(img.getdata())
    ch  = [ASCII_CHARS[int(p / 256 * len(ASCII_CHARS))] for p in px]
    lines = []
    for i in range(0, len(ch), WIDTH):
        lines.append("".join(ch[i:i+WIDTH])[:WIDTH])
    return "\n".join(lines)


# --- Page output ---

# #!c=0 disables client-side caching so every visit fetches a fresh frame.
# Without this, MeshChat and other clients would serve a stale cached copy.
print("#!c=0")

# Micron header bar using box-drawing characters and colour codes.
# `F0f2 = foreground colour (cyan-ish), `Ffd0 = yellow, `b/`B = bold on/off
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`Ffd0`b  WEBCAM - VM158  `B`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`f")
print("")

# Use a temp file in /tmp so we are guaranteed write permission
# regardless of which user NomadNet is running as.
with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False, dir="/tmp") as f:
    tmppath = f.name

try:
    if capture(tmppath):
        # Micron literal/preformatted block — content inside ``` is rendered
        # with a monospace font and no further Micron interpretation, which
        # is essential for ASCII art to display correctly.
        print("```")
        print(to_ascii(tmppath))
        print("```")
    else:
        # `cF00 = red foreground, `! = bold, `c`! = reset both
        print("`cF00`!Camera capture failed`c`!")

except Exception as e:
    print("`cF00`!Error: " + str(e) + "`c`!")

finally:
    # Always clean up the temp file, even if an exception occurred above.
    try:
        os.unlink(tmppath)
    except:
        pass

print("")
# `F888 = dark grey — subdued footer hint
print("`F888  Reload page to refresh`f")
