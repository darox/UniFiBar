#!/bin/bash
# UniFi API Endpoint Probe
# Usage: bash probe_endpoints.sh <controller_url> <api_key>
# Example: bash probe_endpoints.sh https://192.168.2.1 f81179df...

CONTROLLER="$1"
API_KEY="$2"

if [ -z "$CONTROLLER" ] || [ -z "$API_KEY" ]; then
    echo "Usage: bash probe_endpoints.sh <controller_url> <api_key>"
    exit 1
fi

# Strip trailing slash
CONTROLLER="${CONTROLLER%/}"

HEADER="X-API-KEY: $API_KEY"
NOW_MS=$(($(date +%s) * 1000))
HOUR_AGO_MS=$((NOW_MS - 3600000))

endpoints=(
    "GET|/proxy/network/api/s/default/rest/alarm|alarms_rest"
    "GET|/proxy/network/api/s/default/list/alarm|alarms_list"
    "GET|/proxy/network/api/s/default/stat/ips/event|ips_events"
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