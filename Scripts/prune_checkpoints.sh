#!/usr/bin/env bash
# Delete the T3 Code checkpoint refs and the reflogs that still reach them.
#
# The checkpoints commit the whole working tree, ignored files included, so they
# can hold live secrets. Run this after a scan failure, then rotate the
# credential. See docs/development.md and issue #32.
set -euo pipefail

cd "$(dirname "$0")/.."

refs=$(git for-each-ref --format='%(refname)' refs/t3)
if [ -n "$refs" ]; then
    echo "==> Deleting $(printf '%s\n' "$refs" | wc -l | tr -d ' ') checkpoint refs"
    while read -r ref; do
        git update-ref -d "$ref"
    done <<< "$refs"
else
    echo "==> No checkpoint refs found"
fi

echo "==> Expiring reflogs and pruning unreachable objects"
git reflog expire --expire=now --all
git gc --prune=now

echo "==> Remaining refs/t3 refs: $(git for-each-ref --format='%(refname)' refs/t3 | wc -l | tr -d ' ')"
