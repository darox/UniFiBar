#!/bin/bash
set -euo pipefail
# UniFi API Endpoint Probe
# Usage: bash probe_endpoints.sh <controller_url>
# The API key is read from the UNIFIBAR_API_KEY environment variable.
# Example: UNIFIBAR_API_KEY=your_key bash probe_endpoints.sh https://192.168.2.1

CONTROLLER="$1"
API_KEY="${UNIFIBAR_API_KEY:-}"

if [ -z "$CONTROLLER" ] || [ -z "$API_KEY" ]; then
    echo "Usage: UNIFIBAR_API_KEY=<key> bash probe_endpoints.sh <controller_url>"
    exit 1
fi

# Strip trailing slash
CONTROLLER="${CONTROLLER%/}"

HEADER="X-API-KEY: $API_KEY"

endpoints=(
    "GET|/proxy/network/api/s/default/rest/dynamicdns|ddns"
    "GET|/proxy/network/api/s/default/rest/portforward|portforwards"
    "GET|/proxy/network/api/s/default/stat/rogueap|rogueaps"
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

    # Note: -sk disables TLS certificate verification for self-signed UniFi controllers.
    # For production use, remove -k to enforce certificate validation.
    if [ "$method" = "POST" ]; then
        response=$(curl -sk -w "\n__HTTP_CODE__%{http_code}" \
            -X POST -H "$HEADER" -H "Content-Type: application/json" \
            -d '{"type":"by_cat"}' "$url" 2>/dev/null)
    else
        response=$(curl -sk -w "\n__HTTP_CODE__%{http_code}" "$url" -H "$HEADER" 2>/dev/null)
    fi

    http_code=$(echo "$response" | grep "__HTTP_CODE__" | sed 's/__HTTP_CODE__//')
    body=$(echo "$response" | grep -v "__HTTP_CODE__")

    echo "HTTP $http_code"
    echo "$body" | head -c 800
    echo ""
    echo ""
done