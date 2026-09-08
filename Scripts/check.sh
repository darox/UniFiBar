#!/bin/bash
set -euo pipefail

case "${1:-}" in
    ""|--portable) ;;
    *) echo "Usage: bash Scripts/check.sh [--portable]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "Usage: bash Scripts/check.sh [--portable]" >&2
    exit 2
fi
cd "$(dirname "$0")/.."

for script in Scripts/*.sh; do
    bash -n "$script"
done
shellcheck -x -P SCRIPTDIR Scripts/*.sh
python3 Tests/test_build_bundle.py
python3 Tests/test_probe_endpoints.py
git diff --check
git diff --cached --check

if [ "${1:-}" = --portable ]; then
    echo "PASS: portable checks only; Swift tests and macOS QA were not run."
    exit 0
fi
if [ "$(uname -s)" != Darwin ]; then
    echo "BLOCKED: full checks need macOS 26 and Xcode 26 (Swift 6.2+)." >&2
    exit 2
fi

swift test
bash Scripts/package_app.sh
plutil -lint .build/release/UniFiBar.app/Contents/Info.plist
codesign --verify --deep --strict .build/release/UniFiBar.app
echo "PASS: tests and release bundle; run the display QA in docs/development.md."
