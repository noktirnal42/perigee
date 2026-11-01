#!/bin/bash
# Builds the app icons from App/Shared/Art/icon-master.png (orbit grazing a Mars limb).
# iOS: full-bleed 1024 (+dark, +tinted grayscale). macOS: 824px rounded tile on a 1024 canvas with shadow, sized 16–1024.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; M="$ROOT/App/Shared/Art/icon-master.png"
IOS="$ROOT/App/iOS/Assets.xcassets/AppIcon.appiconset"; MAC="$ROOT/App/macOS/Assets.xcassets/AppIcon.appiconset"
magick "$M" -resize 1024x1024! "$IOS/icon-ios.png"
cp "$IOS/icon-ios.png" "$IOS/icon-ios-dark.png"
magick "$M" -resize 1024x1024! -colorspace Gray -level 4%,100% "$IOS/icon-ios-tinted.png"
TILE=$(mktemp -t perigee-tile).png
magick "$M" -resize 824x824! \( -size 824x824 xc:none -fill white -draw "roundrectangle 0,0 823,823 185,185" \) -alpha set -compose DstIn -composite "$TILE"
magick -size 1024x1024 xc:none \( "$TILE" \( +clone -background black -shadow 45x14+0+14 \) +swap -background none -layers merge +repage \) -gravity center -composite "$MAC/icon_mac_1024.png"
for base in 16 32 128 256 512; do for s in 1 2; do
  magick "$MAC/icon_mac_1024.png" -resize $((base*s))x$((base*s)) "$MAC/icon_${base}x${base}@${s}x.png"
done; done
rm -f "$MAC/icon_mac_1024.png" "$TILE"
echo "icons written"
