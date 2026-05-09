#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="UniFiBar"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Source version info (with defaults)
APP_VERSION="0.0.0"
BUILD_NUMBER="0"
if [ -f "$PROJECT_DIR/version.env" ]; then
    source "$PROJECT_DIR/version.env"
fi

# Source shared bundle assembly
source "$SCRIPT_DIR/build_common.sh"

echo "==> Killing existing $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "==> Building $APP_NAME (debug)..."
cd "$PROJECT_DIR"
swift build 2>&1

BINARY="$BUILD_DIR/debug/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

assemble_app_bundle "$APP_BUNDLE" "$BINARY" "$PROJECT_DIR" "$BUILD_DIR"

echo "==> Signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Launching $APP_NAME..."
open "$APP_BUNDLE"

echo "==> Done! $APP_NAME is running."