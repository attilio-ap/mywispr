#!/bin/bash
# Generates AppIcon.icns from a single square source image.
#
# Usage:
#   ./create_icon.sh path/to/icon-source.png
#
# The source should be square and at least 1024x1024 for a crisp result.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <source-image>"
    echo "  The source image should be square, ideally 1024x1024 or larger."
    exit 1
fi

INPUT_IMAGE="$1"
ICONSET_DIR="AppIcon.iconset"

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: source image not found: $INPUT_IMAGE"
    exit 1
fi

echo "=== Generating icons from $INPUT_IMAGE ==="

# Clean any leftovers from a previous run, then build the iconset.
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# macOS expects each nominal size at both 1x and 2x.
generate() {
    local size="$1" name="$2"
    sips -s format png -z "$size" "$size" "$INPUT_IMAGE" --out "$ICONSET_DIR/$name.png" > /dev/null
}

generate 16   icon_16x16
generate 32   icon_16x16@2x
generate 32   icon_32x32
generate 64   icon_32x32@2x
generate 128  icon_128x128
generate 256  icon_128x128@2x
generate 256  icon_256x256
generate 512  icon_256x256@2x
generate 512  icon_512x512
generate 1024 icon_512x512@2x

iconutil -c icns "$ICONSET_DIR"
rm -rf "$ICONSET_DIR"

echo "=== AppIcon.icns created successfully ==="
