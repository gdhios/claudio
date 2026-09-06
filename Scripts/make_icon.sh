#!/bin/bash
# Generates icon/AppIcon.icns from the master SVGs:
#   icon/claudio_icon.svg       — detailed artwork (physical sizes >= 64 px)
#   icon/claudio_icon_small.svg — simplified artwork (16 and 32 px, legibility)
# Requires rsvg-convert (brew install librsvg).
# Usage: Scripts/make_icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RSVG="$(command -v rsvg-convert || echo /opt/homebrew/bin/rsvg-convert)"

mkdir -p icon
"$RSVG" -w 1024 -h 1024 icon/claudio_icon.svg -o icon/icon_1024.png

ICONSET="icon/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { # render <svg> <px> <file>
    "$RSVG" -w "$2" -h "$2" "$1" -o "$ICONSET/$3"
}

# Small physical sizes (16/32 px): simplified variant.
render icon/claudio_icon_small.svg 16  icon_16x16.png
render icon/claudio_icon_small.svg 32  icon_16x16@2x.png
render icon/claudio_icon_small.svg 32  icon_32x32.png
# From 64 px physical and up: detailed artwork.
render icon/claudio_icon.svg       64  icon_32x32@2x.png
render icon/claudio_icon.svg      128  icon_128x128.png
render icon/claudio_icon.svg      256  icon_128x128@2x.png
render icon/claudio_icon.svg      256  icon_256x256.png
render icon/claudio_icon.svg      512  icon_256x256@2x.png
render icon/claudio_icon.svg      512  icon_512x512.png
render icon/claudio_icon.svg     1024  icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o icon/AppIcon.icns
rm -rf "$ICONSET"
echo "✅ icon/AppIcon.icns"
