#!/bin/bash
# Make the app icon the way macOS expects it: the square artwork is clipped to the rounded "squircle" shape that fills the whole
# 1024 px canvas, corners transparent, no margin and no shadow.
# macOS does NOT round the corners of an app icon itself, so a square PNG shows square corners in the Dock and Finder.
#
#   scripts/make-app-icon.sh [source.png]     default source: Resources/AppIconSource/OpenKey-1024-source.png (square, 1024 px)
#
# Writes the one file the app uses: Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024 px). Xcode makes the other sizes at build time.
# Needs ImageMagick (brew install imagemagick) and python3.
set -euo pipefail

MODERN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Sources/OpenKey/macOS/ModernKey"
SOURCE="${1:-$MODERN/Resources/AppIconSource/OpenKey-1024-source.png}"
ICONSET="$MODERN/Assets.xcassets/AppIcon.appiconset"
MASTER="$ICONSET/AppIcon.png"
command -v magick >/dev/null || { echo "error: ImageMagick (magick) not found" >&2; exit 1; }
[ -f "$SOURCE" ] || { echo "error: $SOURCE not found" >&2; exit 1; }
[ -d "$ICONSET" ] || { echo "error: $ICONSET not found" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SHAPE=1024     # the icon body on the 1024 canvas: all of it
OFFSET=0

# Mask: a superellipse |x|^5 + |y|^5 = 1 is close to Apple's continuous-corner rounded square
python3 -I - "$SHAPE" "$OFFSET" > "$WORK/points.txt" <<'EOF'
import math, sys
size, off = int(sys.argv[1]), int(sys.argv[2])
n, half, c = 5.0, size / 2.0, off + size / 2.0
pts = []
steps = 720
for i in range(steps):
    t = 2 * math.pi * i / steps
    cs, sn = math.cos(t), math.sin(t)
    x = math.copysign(abs(cs) ** (2 / n), cs) * half + c
    y = math.copysign(abs(sn) ** (2 / n), sn) * half + c
    pts.append(f"{x:.2f},{y:.2f}")
print(" ".join(pts))
EOF
magick -size 1024x1024 xc:black -fill white -draw "polygon $(cat "$WORK/points.txt")" -blur 0x0.6 "$WORK/mask.png"

# Body: the artwork scaled into the shape and clipped to it
magick "$SOURCE" -resize ${SHAPE}x${SHAPE}! -background none -gravity center -extent 1024x1024 "$WORK/art.png"
magick "$WORK/art.png" "$WORK/mask.png" -alpha off -compose CopyOpacity -composite "$WORK/body.png"

magick "$WORK/body.png" -colorspace sRGB -define png:color-type=6 "$MASTER"

echo "icon written: $MASTER"
