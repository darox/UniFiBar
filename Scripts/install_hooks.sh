#!/usr/bin/env bash
# Point Git at the versioned hooks in Scripts/hooks.
set -euo pipefail

cd "$(dirname "$0")/.."

chmod +x Scripts/hooks/pre-push
git config core.hooksPath Scripts/hooks
echo "==> Git hooks installed from Scripts/hooks (core.hooksPath)"
