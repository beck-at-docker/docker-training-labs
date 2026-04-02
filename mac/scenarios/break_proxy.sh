#!/bin/bash
# break_proxy.sh - Corrupts proxy settings on Mac Docker Desktop
#
# On Mac, Docker Desktop manages proxy config via settings-store.json.
# However, on Business/Enterprise accounts, the backend loads admin/cloud
# policy from hub.docker.com on every cold start and applies it as a
# startup override. On this account, that policy forces ProxyHTTPMode
# back to "system" before the daemon fully initialises, which means
# writing "manual" to settings-store.json while Docker is stopped has
# no effect — the admin override silently reverts it.
#
# This script therefore applies the proxy settings while Docker is
# running, via the backend socket API (the same path the Docker Desktop
# UI uses). Because the admin policy marks proxy mode as unlocked
# (locked: false), user-initiated API changes are accepted and
# propagate immediately to the internal httpproxy process without
# requiring a full application restart.
#
# Two separate mechanisms are used to simulate layered misconfiguration:
#
#   1. Backend API: sets ProxyHTTPMode to "manual" and points both the
#      daemon-level and container-level proxy to 192.0.2.1:8080, an
#      RFC 5737 TEST-NET address that silently drops all traffic.
#
#   2. Shell RC file (~/.zshrc or ~/.bash_profile): exports HTTP_PROXY
#      and HTTPS_PROXY so the environment variable layer is also broken.
#      Wrapped in sentinel markers for clean programmatic removal.
#
# Both are backed up before modification.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKEND_SOCK="$HOME/Library/Containers/com.docker.docker/Data/backend.sock"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BOGUS_PROXY="http://192.0.2.1:8080"

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
# fix_proxy() in lib/fix.sh restores from this backup.
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"
echo "  Settings store backed up"

# ------------------------------------------------------------------
# Method 1: Apply proxy settings via the Docker Desktop backend API.
#
# Writing to settings-store.json while Docker is stopped does not
# survive the startup admin-settings override on this account. The
# backend API applies changes through the same code path used by the
# Docker Desktop UI and propagates the new proxy config to the live
# httpproxy process immediately — no Docker restart required.
#
# The POST body uses the nested API format (vm.proxy / vm.containersProxy).
# Both the daemon-level proxy and the container-level proxy are set so
# that both docker pull and container internet access fail.
# ------------------------------------------------------------------
echo ""
echo "Applying proxy settings via Docker Desktop backend API..."

PAYLOAD=$(python3 -c "
import json
proxy = '$BOGUS_PROXY'
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
    -o /tmp/proxy-break-api-response.txt \
    "http://localhost/app/settings" \
    -d "$PAYLOAD" 2>&1) || true

API_RESPONSE=$(cat /tmp/proxy-break-api-response.txt 2>/dev/null || true)
rm -f /tmp/proxy-break-api-response.txt

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
    echo "  API call succeeded (HTTP $HTTP_STATUS)"
else
    echo "  Error: API returned HTTP $HTTP_STATUS"
    echo "  Response: $API_RESPONSE"
    echo "  The proxy break was not applied."
    exit 1
fi

# ------------------------------------------------------------------
# Method 2: Corrupt shell RC file with bogus proxy env vars.
# This injects the environment variable layer on top of the
# daemon-level break, creating a two-layer misconfiguration.
# ------------------------------------------------------------------
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.zshrc"
fi

if [ -f "$SHELL_RC" ]; then
    cp "$SHELL_RC" "${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
fi

cat >> "$SHELL_RC" << 'EOF'

# BEGIN DOCKER TRAINING LAB PROXY BREAK - DO NOT EDIT
# These settings were added by the Docker training lab break script
export HTTP_PROXY=http://192.0.2.1:8080
export HTTPS_PROXY=http://192.0.2.1:8080
export NO_PROXY=
# END DOCKER TRAINING LAB PROXY BREAK
EOF

echo "  Shell RC updated: $SHELL_RC"

# ------------------------------------------------------------------
# Wait for the proxy to become observable.
#
# The API applies settings to the live httpproxy process immediately,
# but there can be a brief lag before docker info reflects the change.
# Poll for up to 30 seconds before declaring success.
# ------------------------------------------------------------------
echo ""
echo "  Waiting for proxy settings to take effect..."
PROXY_ACTIVE=0
for i in $(seq 1 15); do
    # Primary check: docker info should report the bogus proxy address
    if docker info 2>/dev/null | grep -q "192.0.2.1"; then
        PROXY_ACTIVE=1
        break
    fi

    # Secondary check: attempt a pull and look for the bogus proxy
    # address in the failure output
    PULL_ERR=$(docker pull hello-world:latest 2>&1 || true)
    if echo "$PULL_ERR" | grep -q "192.0.2.1"; then
        PROXY_ACTIVE=1
        break
    fi

    sleep 2
done

if [ "$PROXY_ACTIVE" -eq 0 ]; then
    echo "  Warning: proxy not yet visible in docker info or pull output after 30s"
    echo "  Settings were applied via the API — the break may still be active."
    echo "  Try: docker pull hello-world (should time out or fail with a proxy error)"
fi

echo ""
echo "Docker Desktop broken"
echo "Backups saved:"
echo "  ${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"
echo "  ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptoms: Image pulls fail, container internet access fails"
