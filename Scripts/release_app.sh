#!/usr/bin/env bash
# Build, sign with a Developer ID, notarize and staple a release zip.
#
# Prerequisites:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. Notary credentials stored once with:
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#            --team-id TEAMID --apple-id you@example.com
#
# Environment: DEVELOPER_ID overrides the detected identity,
#              NOTARY_PROFILE defaults to unifibar-notary.
set -euo pipefail

source "$(dirname "$0")/build_common.sh"
init_build_env release
cd "$PROJECT_DIR"

NOTARY_PROFILE="${NOTARY_PROFILE:-unifibar-notary}"
IDENTITY="${DEVELOPER_ID:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
    echo "ERROR: no Developer ID Application identity found." >&2
    echo "Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
    exit 1
fi

echo "==> Building $APP_NAME $APP_VERSION ($BUILD_NUMBER)"
bash Scripts/package_app.sh

echo "==> Signing with '$IDENTITY' (hardened runtime)"
codesign --force --options runtime --timestamp \
    --entitlements "$PROJECT_DIR/UniFiBar.entitlements" \
    --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

DIST="$PROJECT_DIR/dist"
mkdir -p "$DIST"
UPLOAD="$DIST/$APP_NAME-$APP_VERSION-upload.zip"
FINAL="$DIST/$APP_NAME-$APP_VERSION.zip"

echo "==> Notarizing (this waits for Apple)"
ditto -c -k --keepParent "$APP_BUNDLE" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$UPLOAD"

echo "==> Stapling the ticket"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$FINAL"
ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"

echo "==> Done: $FINAL"
echo "    Upload it with: gh release upload v$APP_VERSION \"$FINAL\""
