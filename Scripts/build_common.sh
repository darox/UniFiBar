#!/bin/bash
# Shared bundle assembly functions for UniFiBar build scripts.
# Source this file: source "$(dirname "$0")/build_common.sh"

assemble_app_bundle() {
    local APP_BUNDLE="$1"
    local BINARY="$2"
    local PROJECT_DIR="$3"
    local BUILD_DIR="$4"

    echo "==> Assembling $(basename "$APP_BUNDLE") bundle..."
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
    <key>NSLocalNetworkUsageDescription</key>
    <string>UniFiBar needs access to your local network to connect to your UniFi controller.</string>
</dict>
</plist>
PLIST

    # Copy entitlements
    if [ -f "$PROJECT_DIR/UniFiBar.entitlements" ]; then
        cp "$PROJECT_DIR/UniFiBar.entitlements" "$APP_BUNDLE/Contents/Resources/"
    fi

    # Generate .icns from app icon PNGs (if available)
    local ICON_SRC="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
    if [ -d "$ICON_SRC" ]; then
        local ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"
        cp "$ICON_SRC/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png" 2>/dev/null || true
        cp "$ICON_SRC/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    else
        echo "WARNING: App icon assets not found at $ICON_SRC, skipping icon generation"
    fi

    # Copy status bar icon (if available)
    local STATUSBAR_SRC="$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset"
    if [ -d "$STATUSBAR_SRC" ]; then
        cp "$STATUSBAR_SRC/icon@1x.png" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
        cp "$STATUSBAR_SRC/icon@2x.png" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    else
        echo "WARNING: Status bar icon assets not found, skipping"
    fi
}