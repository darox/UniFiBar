#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

echo "==> Generating placeholder icon..."

mkdir -p "$ICONSET_DIR"

# Generate a simple placeholder icon using sips if a source PNG exists
SOURCE_PNG="$PROJECT_DIR/Resources/AppIcon.png"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "No source icon found at $SOURCE_PNG"
    echo "To generate icons, place a 1024x1024 PNG at Resources/AppIcon.png"
    echo "Then re-run this script."
    exit 0
fi

SIZES=(16 32 64 128 256 512 1024)
for size in "${SIZES[@]}"; do
    sips -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1
done

# Create @2x variants
cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

# Remove non-standard sizes
rm -f "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"

iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"
echo "==> Icon generated at $BUILD_DIR/AppIcon.icns"
