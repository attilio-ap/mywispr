#!/bin/bash
set -e

INPUT_IMAGE="/Users/attilio/.gemini/antigravity-cli/brain/5ba09116-20ee-4881-ad8e-6ebc665610c1/app_icon_base_1782674019493.jpg"
ICONSET_DIR="AppIcon.iconset"

echo "=== Generazione icone in corso ==="

# 1. Crea la cartella temporanea per l'iconset
mkdir -p "$ICONSET_DIR"

# 2. Genera le varie dimensioni necessarie per macOS
sips -s format png -z 16 16     "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$INPUT_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

# 3. Compila in file .icns
iconutil -c icns "$ICONSET_DIR"

# 4. Pulisci la cartella temporanea
rm -rf "$ICONSET_DIR"

echo "=== AppIcon.icns creata con successo! ==="
