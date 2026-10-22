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

# Copy a file below the trusted project root without following symbolic links.
# The optional fourth argument permits a missing source for build resources.
copy_trusted_file() {
    local root="${1:?trusted project root required}"
    local source="${2:?source path required}"
    local destination="${3:?destination required}"
    local optional="${4:-false}"
    local current component remaining relative

    root="${root%/}"
    case "$source" in
        "$root"/*) relative="${source#"$root"/}" ;;
        *)
            echo "ERROR: source '$source' is outside trusted project root '$root'" >&2
            return 1
            ;;
    esac

    current="$root"
    remaining="$relative"
    while [ -n "$remaining" ]; do
        if [[ "$remaining" == */* ]]; then
            component="${remaining%%/*}"
            remaining="${remaining#*/}"
        else
            component="$remaining"
            remaining=""
        fi
        case "$component" in
            ""|.|..)
                echo "ERROR: invalid source path component '$component' in '$source'" >&2
                return 1
                ;;
        esac
        current="$current/$component"
        if [[ -L "$current" ]]; then
            echo "ERROR: refusing to copy through symbolic link '$current'" >&2
            return 1
        fi
    done

    if [[ ! -e "$current" && "$optional" == "true" ]]; then
        return 0
    fi
    if [[ ! -f "$current" ]]; then
        echo "ERROR: source '$source' is not a regular file" >&2
        return 1
    fi
    cp -P "$current" "$destination"
}

copy_optional_trusted_file() {
    copy_trusted_file "$1" "$2" "$3" true
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
    copy_optional_trusted_file "$PROJECT_DIR" "$PROJECT_DIR/UniFiBar.entitlements" \
        "$APP_BUNDLE/Contents/Resources/"

    # Generate .icns from app icon PNGs (if available)
    local ICON_SRC="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
    if [ -d "$ICON_SRC" ]; then
        local ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
        local icon_name
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"
        for icon_name in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
            icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
            icon_512x512.png icon_512x512@2x.png; do
            copy_optional_trusted_file "$PROJECT_DIR" "$ICON_SRC/$icon_name" "$ICONSET_DIR/"
        done
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    else
        echo "WARNING: App icon assets not found at $ICON_SRC, skipping icon generation"
    fi

    # Copy status bar icon (if available)
    local STATUSBAR_SRC="$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset"
    if [ -d "$STATUSBAR_SRC" ]; then
        copy_optional_trusted_file "$PROJECT_DIR" "$STATUSBAR_SRC/icon@1x.png" \
            "$APP_BUNDLE/Contents/Resources/"
        copy_optional_trusted_file "$PROJECT_DIR" "$STATUSBAR_SRC/icon@2x.png" \
            "$APP_BUNDLE/Contents/Resources/"
    else
        echo "WARNING: Status bar icon assets not found, skipping"
    fi
}
