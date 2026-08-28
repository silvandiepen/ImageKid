#!/usr/bin/env bash
#
# Fill an .appiconset from one square source image.
#
#   ./scripts/make-appicon.sh ~/sculptor-icon.png SculptorAppIcon
#
# The source should be at least 1024x1024 so the @2x 512 slice is not upscaled.
# Uses sips, which ships with macOS; no dependencies.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <source.png> <IconSetName>" >&2
  exit 2
fi

source_image="$1"
icon_set="$2"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$here/Sources/ImageKid/Resources/Assets.xcassets/${icon_set}.appiconset"

if [ ! -f "$source_image" ]; then
  echo "no such file: $source_image" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "no such icon set: $target" >&2
  exit 1
fi

width=$(sips -g pixelWidth "$source_image" | awk '/pixelWidth/ {print $2}')
height=$(sips -g pixelHeight "$source_image" | awk '/pixelHeight/ {print $2}')
if [ "$width" != "$height" ]; then
  echo "source must be square; got ${width}x${height}" >&2
  exit 1
fi
if [ "$width" -lt 1024 ]; then
  echo "warning: source is ${width}px; 1024 or larger avoids upscaling" >&2
fi

# base name : pixel size
slices=(
  "icon_16x16:16"
  "icon_16x16@2x:32"
  "icon_32x32:32"
  "icon_32x32@2x:64"
  "icon_128x128:128"
  "icon_128x128@2x:256"
  "icon_256x256:256"
  "icon_256x256@2x:512"
  "icon_512x512:512"
  "icon_512x512@2x:1024"
)

for slice in "${slices[@]}"; do
  name="${slice%%:*}"
  size="${slice##*:}"
  sips --resampleHeightWidth "$size" "$size" \
    --setProperty format png \
    "$source_image" --out "$target/$name.png" >/dev/null
done

echo "wrote ${#slices[@]} slices to $target"
