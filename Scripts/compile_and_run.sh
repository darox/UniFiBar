#!/bin/bash
set -euo pipefail

# Shared paths, version info and bundle assembly
source "$(dirname "$0")/build_common.sh"
init_build_env debug

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