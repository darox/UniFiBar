#!/bin/bash
# Runs the synthetic model microbenchmark in Tests/benchmark_sessions.swift.
# Not part of check.sh. Run it by hand when changing session aggregation or
# WiFiStatus hot paths. No app launch, controller, or credentials involved.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(mktemp -t unifibar-bench)"
trap 'rm -f "$out"' EXIT

swiftc -O -swift-version 6 -disable-sandbox -module-name UniFiBarBench \
    -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx26.0" \
    Sources/UniFiBar/Models/*.swift Sources/UniFiBar/Utils/Formatters.swift \
    Tests/benchmark_sessions.swift -o "$out"

"$out"
