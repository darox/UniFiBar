#!/bin/bash
# Shared bundle assembly functions for UniFiBar build scripts.
# Source this file: source "$(dirname "$0")/build_common.sh"

# Project paths and version loading for the build entry points. Sets SCRIPT_DIR,
# PROJECT_DIR, APP_NAME, BUILD_DIR, APP_BUNDLE, APP_VERSION and BUILD_NUMBER in the
# caller's scope. $1 is the Swift build configuration (debug or release).
init_build_env() {
    local config="${1:?build configuration required}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    APP_NAME="UniFiBar"
    BUILD_DIR="$PROJECT_DIR/.build"
    APP_BUNDLE="$BUILD_DIR/$config/$APP_NAME.app"

    APP_VERSION="0.0.0"
    BUILD_NUMBER="0"
    if [ -f "$PROJECT_DIR/version.env" ]; then
        # Parse, never source: version.env is tracked, so a pull request can change it.
        while IFS='=' read -r key value || [ -n "$key" ]; do
            case "$key" in
                APP_VERSION) APP_VERSION="$value" ;;
                BUILD_NUMBER) BUILD_NUMBER="$value" ;;
            esac
        done < "$PROJECT_DIR/version.env"
    fi
    validate_version_info
}

# Guard the plist writer against any version value that is not a plain number
# before it reaches XML, even though init_build_env only parses the file.
validate_version_info() {
    if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        echo "ERROR: APP_VERSION '$APP_VERSION' must look like 1.2.3" >&2
        exit 1
    fi
    if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "ERROR: BUILD_NUMBER '$BUILD_NUMBER' must be a positive integer" >&2
        exit 1
    fi
}

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
        cp "$ICON_SRC"/icon_{16x16,32x32,128x128,256x256,512x512}{,@2x}.png "$ICONSET_DIR/" 2>/dev/null || true
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
