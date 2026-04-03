#!/bin/bash
# break_proxyfail.sh - Simulates a proxy misconfiguration where Docker Desktop
# is configured to use a proxy that actively refuses connections.
#
# Based on real support cases where Docker Desktop had a manual proxy set to an
# address that was not running - specifically a localhost port with nothing
# listening on it. This produces an immediate "connection refused" error, which
# is diagnostically distinct from the silent-drop timeout that the PROXY lab
# produces using a non-routable RFC 5737 address (192.0.2.1).
#
# The difference in symptom is the teaching point:
#
#   PROXY lab (192.0.2.1:8080):   packets routed but silently dropped
#                                 -> connection timeout after a wait
#   This lab (127.0.0.1:9753):    packets delivered, port not listening
#                                 -> immediate "connection refused" error
#
# Port 9753 is chosen because it is above the privileged range (no sudo
# required to inspect it), is not a commonly used application port, and is
# very unlikely to be occupied on a typical developer workstation.
#
# WHY THE BACKEND API IS USED (not direct settings-store.json writes):
#
# On Business/Enterprise accounts, Docker Desktop pulls admin/cloud policy
# from hub.docker.com on every cold start and applies it as a startup
# override. Writing "manual" to settings-store.json while Docker is stopped
# has no effect — the admin policy silently reverts ProxyHTTPMode back to
# "system" before the daemon fully initialises.
#
# This script therefore applies the proxy settings while Docker is running,
# via the backend socket API (the same path the Docker Desktop UI uses).
# Because the admin policy marks proxy mode as unlocked (locked: false),
# user-initiated API changes are accepted and propagate immediately to the
# internal httpproxy process without requiring a full application restart.
#
# This lab modifies proxy settings via the API only. It intentionally does
# not corrupt the shell RC file; the diagnostic focus is on reading Docker
# Desktop's proxy configuration directly from the settings store.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKEND_SOCK="$HOME/Library/Containers/com.docker.docker/Data/backend.sock"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BROKEN_PROXY="http://127.0.0.1:9753"

echo "Breaking Docker Desktop..."

# ------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

if [ ! -f "$SETTINGS_STORE" ]; then
    echo "Error: Docker Desktop settings store not found at:"
    echo "  $SETTINGS_STORE"
    exit 1
fi

if [ ! -S "$BACKEND_SOCK" ]; then
    echo "Error: Docker Desktop backend socket not found at:"
    echo "  $BACKEND_SOCK"
    echo "  Is Docker Desktop fully started?"
    exit 1
fi

# ------------------------------------------------------------------
# Backup current settings BEFORE the break is applied.
# fix_proxyfail() in lib/fix.sh restores from this backup.
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-proxyfail-${BACKUP_TIMESTAMP}"
echo "  Settings store backed up"

# ------------------------------------------------------------------
# Apply the loopback proxy via the Docker Desktop backend API.
#
# 127.0.0.1:9753 routes to the local machine's TCP stack, which responds
# immediately with "connection refused" because nothing is listening on
# that port. Both daemon-level and container-level proxy keys are set so
# both docker pull and container internet access fail consistently.
#
# The POST body uses the nested API format (vm.proxy / vm.containersProxy).
# ------------------------------------------------------------------
echo ""
echo "Applying proxy settings via Docker Desktop backend API..."

PAYLOAD=$(python3 -c "
import json
proxy = '$BROKEN_PROXY'
print(json.dumps({
    'vm': {
        'proxy': {
            'mode':    {'value': 'manual'},
            'http':    {'value': proxy},
            'https':   {'value': proxy},
            'exclude': {'value': ''}
        },
        'containersProxy': {
            'mode':    {'value': 'manual'},
            'http':    {'value': proxy},
            'https':   {'value': proxy},
            'exclude': {'value': ''}
        }
    }
}, indent=2))
")

HTTP_STATUS=$(curl \
    --silent \
    --show-error \
    --unix-socket "$BACKEND_SOCK" \
    -X POST \
    -H "Content-Type: application/json" \
    -w "%{http_code}" \
    -o /tmp/proxyfail-break-api-response.txt \
    "http://localhost/app/settings" \
    -d "$PAYLOAD" 2>&1) || true

API_RESPONSE=$(cat /tmp/proxyfail-break-api-response.txt 2>/dev/null || true)
rm -f /tmp/proxyfail-break-api-response.txt

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
    echo "  API call succeeded (HTTP $HTTP_STATUS)"
else
    echo "  Error: API returned HTTP $HTTP_STATUS"
    echo "  Response: $API_RESPONSE"
    echo "  The proxy break was not applied."
    exit 1
fi

# ------------------------------------------------------------------
# Wait for the loopback proxy to become observable.
#
# The API applies settings to the live httpproxy process immediately,
# but there is a brief lag before docker info reflects the change.
# Poll for up to 30 seconds before declaring success.
#
# Primary check: docker info should report the loopback proxy address.
# Secondary check: attempt a pull and look for connection refused,
# which confirms the broken proxy is actively intercepting traffic.
# ------------------------------------------------------------------
echo ""
echo "  Waiting for proxy settings to take effect..."
PROXY_ACTIVE=0
for i in $(seq 1 15); do
    # Primary: proxy address visible in docker info
    if docker info 2>/dev/null | grep -q "127.0.0.1:9753"; then
        PROXY_ACTIVE=1
        break
    fi

    # Secondary: pull attempt fails with connection refused or loopback address
    PULL_ERR=$(docker pull hello-world:latest 2>&1 || true)
    if echo "$PULL_ERR" | grep -qE "(connection refused|127\.0\.0\.1:9753)"; then
        PROXY_ACTIVE=1
        break
    fi

    sleep 2
done

if [ "$PROXY_ACTIVE" -eq 0 ]; then
    echo "  Warning: loopback proxy not yet visible in docker info or pull output after 30s"
    echo "  Settings were applied via the API — the break may still be active."
    echo "  Try: docker pull hello-world (should fail immediately with connection refused)"
fi

echo ""
echo "Docker Desktop broken"
echo "Backup saved: ${SETTINGS_STORE}.backup-proxyfail-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptoms: Image pulls fail with connection refused; container internet access fails"
