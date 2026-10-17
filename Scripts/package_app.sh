#!/bin/bash
set -euo pipefail

# Shared paths, version info and bundle assembly
source "$(dirname "$0")/build_common.sh"
init_build_env release

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

assemble_app_bundle "$APP_BUNDLE" "$BINARY" "$PROJECT_DIR" "$BUILD_DIR"

echo "==> Signing (ad-hoc, with entitlements)..."
# Xcode placeholders like $(AppIdentifierPrefix) only resolve for provisioning-profile
# builds. In an ad-hoc signature the placeholder stays literal, macOS rejects the
# entitlement, and launchd refuses to start the bundle (verified on macOS 27.2).
ENTITLEMENTS="$PROJECT_DIR/UniFiBar.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    if grep -q '[$](' "$ENTITLEMENTS"; then
        echo "ERROR: $ENTITLEMENTS contains an unresolved \$() placeholder; ad-hoc signing cannot expand it" >&2
        exit 1
    fi
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
    echo "ERROR: $ENTITLEMENTS not found; refusing to sign without entitlements"
    exit 1
fi

echo "==> Done! App bundle at: $APP_BUNDLE"
echo "    Version: $APP_VERSION ($BUILD_NUMBER)"
echo ""
echo "    To install: cp -r \"$APP_BUNDLE\" /Applications/"