#!/home/user/nomadnet-env/bin/python3
#
# webcam-colour.mu — NomadNet dynamic page: live webcam as thermal-style colour ASCII art
#
# This script works identically to webcam.mu but adds per-character Micron
# foreground colour tags to produce a thermal camera effect. Each character
# is coloured according to the brightness of the corresponding pixel:
#
#   dark pixels   → blue / purple  (cold)
#   mid pixels    → green / yellow (warm)
#   bright pixels → orange / red / white (hot)
#
# The colour is applied by emitting a Micron foreground colour tag before
# every character. A Micron colour tag has the format:
#
#   `Frrggbb
#
# where rr, gg, bb are single hex nibbles (0-f) for red, green, blue.
# Example:  `Ff80  = orange (full red, half green, no blue)
#
# Because every character gets its own tag, the output is significantly
# larger than the monochrome version. This is fine over TCP/IP but would
# be very slow over LoRa or packet radio links — use webcam.mu instead
# on bandwidth-constrained networks.
#
# Requirements:
#   - fswebcam:  sudo apt install fswebcam
#   - Pillow:    pip install Pillow  (inside your nomadnet venv)
#   - Executable bit set:  chmod +x webcam-colour.mu
#   - NomadNet must be restarted after adding this file, or
#     page_refresh_interval must be set in ~/.nomadnetwork/config
#
# Tested on:
#   Ubuntu 22.04, NomadNet 0.9.8, Aukey-PC-LM1E camera on /dev/video0

import subprocess
import os
import tempfile
from PIL import Image


# --- Configuration ---

# V4L2 driver prefix + device node for the webcam.
# Use:  v4l2-ctl --list-devices   to confirm the correct device.
CAM_DEVICE = "v4l2:/dev/video0"

# Output dimensions in characters.
# Slightly narrower than the monochrome version because each character
# is preceded by a 5-character Micron colour tag (`Fxxx), making lines
# much longer in raw bytes even though they display at the same width.
WIDTH  = 72
HEIGHT = 36

# ASCII character palette ordered from darkest (index 0) to lightest (index -1).
# '-' and '=' are excluded — Micron interprets lines of those as horizontal rules.
ASCII_CHARS = "@%#*+~;:,. "

# Thermal colour palette mapping pixel brightness (0-255) to Micron colour codes.
#
# Each entry is (max_brightness, micron_colour_code).
# Brightness ranges are checked from darkest to lightest — first match wins.
#
# The palette deliberately follows the classic infrared thermal camera look:
#   very dark → black
#   dark      → deep blue through cyan   (cold zones)
#   mid       → green through yellow     (neutral zones)
#   bright    → orange through red       (warm zones)
#   very bright → near-white             (hottest zones)
#
# You can tune these values to suit your scene. For a mostly dark room,
# shift the thresholds lower so more colours are used in the dark range.
# For a bright outdoor scene, shift them higher.
THERMAL_PALETTE = [
    (20,  "F000"),   # black          — very dark pixels
    (45,  "F00f"),   # deep blue      — dark
    (70,  "F02f"),   # blue-cyan
    (95,  "F0ff"),   # cyan
    (120, "F0f4"),   # cyan-green
    (145, "F0f0"),   # green          — mid brightness
    (170, "Fff0"),   # yellow-green
    (195, "Ffd0"),   # yellow
    (215, "Ff80"),   # orange         — bright
    (235, "Ff20"),   # red-orange
    (245, "Ff00"),   # red
    (255, "Fff5"),   # near-white     — hottest / brightest pixels
]


# --- Functions ---

def capture(path):
    """
    Capture a single JPEG still from the webcam and save it to 'path'.

    -S 5 skips the first 5 frames while the sensor warms up.
    Without this the first frame is typically badly overexposed.

    capture_output=True prevents fswebcam's stderr from appearing in
    the Micron page output and corrupting the colour tags.

    timeout=20 is a Python subprocess timeout (not an fswebcam flag).
    It kills fswebcam if it hangs, preventing NomadNet from blocking.

    Returns True only if fswebcam succeeded AND wrote a non-empty file.
    """
    result = subprocess.run(
        ["/usr/bin/fswebcam",
         "-d", CAM_DEVICE,
         "-r", "320x240",
         "--jpeg", "50",
         "--no-banner",
         "-S", "5",
         "-q", path],
        capture_output=True,
        timeout=20
    )
    return result.returncode == 0 and os.path.getsize(path) > 0


def brightness_to_colour(brightness):
    """
    Map a greyscale pixel brightness value (0-255) to a Micron colour
    code string using the THERMAL_PALETTE lookup table above.

    Returns a string such as 'Ff80' (orange) which is used as:
        '`' + 'Ff80' + char  →  '`Ff80@'

    Falls back to white ('Ffff') if no palette entry matches,
    which should never happen since the last entry covers 255.
    """
    for max_b, colour in THERMAL_PALETTE:
        if brightness <= max_b:
            return colour
    return "Ffff"  # fallback: white


def to_thermal_ascii(path):
    """
    Convert a JPEG image to thermal-coloured ASCII art as Micron markup.

    For each pixel:
      1. Look up the ASCII character from ASCII_CHARS based on brightness
      2. Look up the Micron colour code from THERMAL_PALETTE based on brightness
      3. Emit:  '`' + colour_code + character

    At the end of each row, '`f' resets the foreground colour to the
    terminal default. This prevents colour from the last character in a
    row bleeding into the page elements that follow the image block.

    Both character selection and colour selection are driven by greyscale
    brightness alone — the original colour information in the JPEG is
    discarded during the convert("L") call.
    """
    img = Image.open(path).convert("L")
    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
    px  = list(img.getdata())

    lines = []
    for row in range(HEIGHT):
        line = ""
        for col in range(WIDTH):
            brightness = px[row * WIDTH + col]
            # Map brightness to ASCII character
            char_index = int(brightness / 256 * len(ASCII_CHARS))
            char = ASCII_CHARS[char_index]
            # Map brightness to Micron thermal colour tag
            colour = brightness_to_colour(brightness)
            # Combine: backtick + colour code + character
            line += "`" + colour + char
        # Reset foreground colour at end of each line
        line += "`f"
        lines.append(line)
    return "\n".join(lines)


# --- Page output ---

# #!c=0 disables client-side caching. Every page visit fetches a live frame.
# This must be the very first line printed to stdout.
print("#!c=0")

# Page header using Micron colour and bold tags.
# `F0f2 = teal/cyan,  `Ffd0 = yellow,  `b/`B = bold on/off,  `f = colour reset
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("`Ffd0`b  WEBCAM - VM158  `B`f")
print("`F0f2━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`f")
print("")

# Write captured frame to /tmp — guaranteed writable by any user.
# delete=False required because fswebcam opens the file after this block.
with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False, dir="/tmp") as f:
    tmppath = f.name

try:
    if capture(tmppath):
        # Micron ``` preformatted block renders content verbatim in monospace.
        # This prevents the many backtick characters in the colour tags from
        # being interpreted as nested Micron formatting instructions.
        print("```")
        print(to_thermal_ascii(tmppath))
        print("```")
    else:
        print("`cF00`!Camera capture failed`c`!")

except Exception as e:
    print("`cF00`!Error: " + str(e) + "`c`!")

finally:
    # Always delete the temp file. This script runs on every page request
    # so temp files would accumulate rapidly without explicit cleanup.
    try:
        os.unlink(tmppath)
    except:
        pass

print("")
print("`F888  Reload page to refresh`f")
