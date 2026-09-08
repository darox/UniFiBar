#!/bin/bash
set -euo pipefail
# UniFi API Endpoint Probe
# Usage: bash probe_endpoints.sh <controller_url>
# The API key is read from the UNIFIBAR_API_KEY environment variable.
# Set CURL_CA_BUNDLE to a trusted CA file for private certificates; TLS stays enabled.
# Responses may contain private network data. Redact before sharing.

CONTROLLER="${1:-}"
API_KEY="${UNIFIBAR_API_KEY:-}"

if [ "$#" -ne 1 ] || [ -z "$CONTROLLER" ] || [ -z "$API_KEY" ]; then
    echo "Usage: UNIFIBAR_API_KEY=<key> bash probe_endpoints.sh <https_controller_url>" >&2
    exit 2
fi

case "$CONTROLLER" in
    https://?*) ;;
    *) echo "Controller URL must use HTTPS and include a host" >&2; exit 2 ;;
esac
case "$CONTROLLER" in
    *'@'*|*'?'*|*'#'*|*$'\r'*|*$'\n'*|https:///*)
        echo "Controller URL must not contain credentials, query parameters or fragments" >&2; exit 2 ;;
esac
case "$API_KEY" in
    *$'\r'*|*$'\n'*) echo "API key must not contain line breaks" >&2; exit 2 ;;
esac

# Strip trailing slash
CONTROLLER="${CONTROLLER%/}"

HEADER="X-API-KEY: $API_KEY"

endpoints=(
    "GET|/proxy/network/api/s/default/rest/dynamicdns|ddns"
    "GET|/proxy/network/api/s/default/stat/portforward|portforwards"
    "POST|/proxy/network/api/s/default/stat/rogueap|rogueaps"
)

echo "=== UniFi API Endpoint Probe ==="
echo "Controller: $CONTROLLER"
echo "Time: $(date -u)"
echo ""

for entry in "${endpoints[@]}"; do
    IFS='|' read -r method path label <<< "$entry"
    url="${CONTROLLER}${path}"
    echo "--- $label ---"
    echo "$method $path"

    # Ignore curlrc overrides/globs and keep the API key out of process arguments.
    args=(--disable --globoff --silent --show-error --proto '=https' --connect-timeout 5 --max-time 15
          --header @- --write-out $'\n__HTTP_CODE__%{http_code}')
    if [ "$method" = "POST" ]; then
        args+=(--request POST --header 'Content-Type: application/json' --data '{"within":24}')
    fi
    response=$(curl "${args[@]}" "$url" <<< "$HEADER")

    http_code="${response##*$'\n'__HTTP_CODE__}"
    body="${response%$'\n'__HTTP_CODE__*}"

    echo "HTTP $http_code"
    printf '%.800s\n' "$body"
    echo ""
done
