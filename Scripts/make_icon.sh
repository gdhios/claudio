#!/bin/bash
# Génère icon/AppIcon.icns à partir du dessin Swift.
# Usage : Scripts/make_icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p icon
swift Scripts/draw_icon.swift icon/icon_1024.png

ICONSET="icon/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for s in 16 32 128 256 512; do
    sips -z "$s" "$s" icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o icon/AppIcon.icns
rm -rf "$ICONSET"
echo "✅ icon/AppIcon.icns"
