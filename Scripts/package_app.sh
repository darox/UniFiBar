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

# Source shared bundle assembly
source "$SCRIPT_DIR/build_common.sh"

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

assemble_app_bundle "$APP_BUNDLE" "$BINARY" "$PROJECT_DIR" "$BUILD_DIR"

echo "==> Signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE"

echo "==> Done! App bundle at: $APP_BUNDLE"
echo "    Version: $APP_VERSION ($BUILD_NUMBER)"
echo ""
echo "    To install: cp -r \"$APP_BUNDLE\" /Applications/"