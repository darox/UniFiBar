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

for script in Scripts/*.sh Scripts/hooks/*; do
    bash -n "$script"
done
shellcheck -x -P SCRIPTDIR Scripts/*.sh Scripts/hooks/*

bash Scripts/check_secrets.sh

# A gate that silently skips is not a gate. Locally a missing tool is a warning;
# in CI it fails, because the workflow installs every tool this script needs.
require_tool() {
    local tool="$1" hint="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        return 0
    fi
    if [ -n "${CI:-}" ]; then
        echo "ERROR: $tool is required in CI but is not installed. $hint" >&2
        exit 1
    fi
    echo "SKIP: $tool is not installed; this gate did not run. $hint" >&2
    return 1
}

if require_tool swiftlint "Install it with: brew install swiftlint"; then
    swiftlint lint --strict --no-cache
fi

if require_tool actionlint "Install it with: brew install actionlint"; then
    actionlint
fi
python3 Tests/test_build_bundle.py
python3 Tests/test_probe_endpoints.py
git diff --check
git diff --cached --check

if [ "${1:-}" = --portable ]; then
    echo "PASS: portable checks only; Swift tests and macOS QA were not run."
    exit 0
fi
if [ "$(uname -s)" != Darwin ]; then
    echo "BLOCKED: full checks need macOS 26 or 27 and Xcode 26 or 27 (Swift 6.2 or later)." >&2
    exit 2
fi

swift test
bash Scripts/package_app.sh
plutil -lint .build/release/UniFiBar.app/Contents/Info.plist
codesign --verify --deep --strict .build/release/UniFiBar.app
echo "PASS: tests and release bundle; run the display QA in docs/development.md."
