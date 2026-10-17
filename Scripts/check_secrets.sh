#!/bin/bash
# Tripwire for credential material in tracked files and in reachable history.
# It matches known token shapes, private-key headers and secret-bearing file types.
# It is a tripwire, not proof: an unusual secret shape passes.
set -euo pipefail
cd "$(dirname "$0")/.."

patterns=(
    'AKIA[0-9A-Z]{16}'
    'gh[pousr]_[A-Za-z0-9]{20,}'
    'sk-[A-Za-z0-9]{20,}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'AIza[0-9A-Za-z_-]{35}'
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

fail=0
for pattern in "${patterns[@]}"; do
    hits="$(git grep -InE -e "$pattern" -- . || true)"
    if [ -n "$hits" ]; then
        echo "SECRET PATTERN '$pattern' in tracked files:" >&2
        echo "$hits" >&2
        fail=1
    fi
done

tracked="$(git ls-files)"
shapes='(^|/)\.env$|(^|/)\.envrc$|\.pem$|\.p12$|\.mobileprovision$|(^|/)id_rsa|(^|/)id_ed25519|\.keystore$'
hits="$(printf '%s\n' "$tracked" | grep -E "$shapes" || true)"
if [ -n "$hits" ]; then
    echo "SECRET-BEARING FILE is tracked:" >&2
    echo "$hits" >&2
    fail=1
fi

# Every path any ref has ever added, including tooling refs such as
# refs/t3/checkpoints. A working-tree grep cannot see those.
shapes='(^|/)\.env$|(^|/)\.envrc$|\.pem$|\.p12$|\.mobileprovision$|(^|/)id_rsa|(^|/)id_ed25519|\.keystore$'
history_paths="$(git log --all --pretty=format: --name-only --diff-filter=AM -- . | sed '/^$/d' | sort -u)"
hits="$(printf '%s\n' "$history_paths" | grep -E "$shapes" || true)"
if [ -n "$hits" ]; then
    echo "SECRET-BEARING FILE exists in history (reachable from some ref):" >&2
    echo "$hits" >&2
    fail=1
fi

# Token shapes in reachable history. -l prints commit:path and never the value.
commits=()
while read -r sha; do
    commits+=("$sha")
done < <(git rev-list --all)
if [ "${#commits[@]}" -gt 0 ]; then
    for pattern in "${patterns[@]}"; do
        hits="$(git grep -lE -e "$pattern" "${commits[@]}" -- . 2>/dev/null || true)"
        if [ -n "$hits" ]; then
            echo "SECRET PATTERN '$pattern' in history (commit:path):" >&2
            echo "$hits" >&2
            fail=1
        fi
    done
fi

if [ "$fail" -ne 0 ]; then
    cat >&2 <<'REMEDY'
REMEDY: rotate the exposed credential, then remove it from the object database:
  git for-each-ref --format='%(refname)' refs/t3 | xargs -r -n1 git update-ref -d
  git reflog expire --expire=now --all && git gc --prune=now --aggressive
Ignored files are not safe. Tooling checkpoints commit the whole working tree.
REMEDY
    exit 1
fi
echo "PASS: no credential material found in tracked files or reachable history"
