#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="UniFiBar"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/release/$APP_NAME.app"

# Source version info (with defaults)
APP_VERSION="0.0.0"
BUILD_NUMBER="0"
if [ -f "$PROJECT_DIR/version.env" ]; then
    source "$PROJECT_DIR/version.env"
fi

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Generate Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.unifbar.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Generate .icns from app icon PNGs (if available)
ICON_SRC="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICON_SRC" ]; then
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    cp "$ICON_SRC/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
    cp "$ICON_SRC/icon_16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ICON_SRC/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
    cp "$ICON_SRC/icon_32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ICON_SRC/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
    cp "$ICON_SRC/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ICON_SRC/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
    cp "$ICON_SRC/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ICON_SRC/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
    cp "$ICON_SRC/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
else
    echo "WARNING: App icon assets not found at $ICON_SRC, skipping icon generation"
fi

# Copy status bar icon (if available)
STATUSBAR_SRC="$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset"
if [ -d "$STATUSBAR_SRC" ]; then
    cp "$STATUSBAR_SRC/icon@1x.png" "$APP_BUNDLE/Contents/Resources/"
    cp "$STATUSBAR_SRC/icon@2x.png" "$APP_BUNDLE/Contents/Resources/"
else
    echo "WARNING: Status bar icon assets not found, skipping"
fi

echo "==> Signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE"

echo "==> Done! App bundle at: $APP_BUNDLE"
echo "    Version: $APP_VERSION ($BUILD_NUMBER)"
echo ""
echo "    To install: cp -r \"$APP_BUNDLE\" /Applications/"
