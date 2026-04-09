#!/bin/bash
# scenarios/break_proxy.sh - Corrupts proxy settings on Linux Docker Desktop
#
# Sets invalid proxy configuration via the Docker Desktop backend socket API
# and injects broken HTTP_PROXY/HTTPS_PROXY exports into the user's shell RC
# file, simulating the kind of layered misconfiguration found in corporate
# environments.
#
# WHY THE BACKEND SOCKET API IS USED (not direct daemon.json or
# settings-store.json writes):
#
# On Linux, 'systemctl stop/start docker-desktop' only restarts the Docker
# Desktop GUI frontend. The underlying VM and dockerd keep running. Writing
# to daemon.json or settings-store.json while Docker is running has no effect
# because the live process never re-reads those files; the frontend reconnects
# to the already-running daemon without applying the file changes.
#
# This script therefore applies proxy settings via the backend socket API
# while Docker Desktop is running - the same path the Docker Desktop UI uses.
# The API propagates the change to the live httpproxy process immediately,
# no restart required.
#
# Two separate mechanisms are used to simulate layered misconfiguration:
#
#   1. Backend API: sets ProxyHTTPMode to "manual" and points both the
#      daemon-level and container-level proxy to 192.0.2.1:8080, an
#      RFC 5737 TEST-NET address that silently drops all traffic (producing
#      a connection timeout rather than an immediate refusal).
#
#   2. Shell RC file (~/.bashrc or ~/.bash_profile): exports HTTP_PROXY
#      and HTTPS_PROXY so the environment variable layer is also broken.
#      Wrapped in sentinel markers for clean programmatic removal.
#
# settings-store.json is backed up before the break so that fix_proxy()
# can restore it for the case where Docker Desktop is fully restarted.

set -e

BACKEND_SOCK="$HOME/.docker/desktop/backend.sock"
SETTINGS_STORE="$HOME/.docker/desktop/settings-store.json"
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
if [ -f "$SETTINGS_STORE" ]; then
    cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"
    echo "  Settings store backed up"
fi

# ------------------------------------------------------------------
# Method 1: Apply proxy settings via the Docker Desktop backend API.
#
# The POST body uses the nested API format (vm.proxy / vm.containersProxy).
# Both the daemon-level proxy and the container-level proxy are set so
# that both docker pull and container internet access fail.
#
# 192.0.2.1 is an RFC 5737 TEST-NET address. Packets route into the
# network stack but are silently dropped, producing a timeout. This is
# diagnostically distinct from break_proxyfail.sh which uses 127.0.0.1
# on a closed port and produces an immediate "connection refused".
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
#
# Shell env vars are inherited by child processes of the shell, which
# includes the Docker CLI. However, they do NOT affect the Docker daemon
# (dockerd), which is launched by systemd with its own clean environment.
# A trainee who only fixes the shell RC and never touches the proxy config
# will still fail the docker pull test - both layers must be resolved.
#
# On Linux, ~/.bashrc is the standard interactive shell config.
# ------------------------------------------------------------------
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    # Default to .bashrc on Linux
    SHELL_RC="$HOME/.bashrc"
fi

# Backup the RC file
SHELL_BACKUP_CREATED=0
if [ -f "$SHELL_RC" ]; then
    cp "$SHELL_RC" "${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    SHELL_BACKUP_CREATED=1
fi

# Add broken proxy settings wrapped in sentinel markers for clean removal
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
    echo "  Settings were applied via the API - the break may still be active."
    echo "  Try: docker pull hello-world (should time out or fail with a proxy error)"
fi

echo ""
echo "Docker Desktop broken"
echo ""
echo "Proxy configuration broken in:"
echo "   - Docker Desktop settings (via backend API, persisted to settings-store.json)"
echo "   - $SHELL_RC (CLI-level, requires terminal restart or: source $SHELL_RC)"
echo ""
echo "Backups saved:"
[ -f "${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}" ] && \
    echo "   - ${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"
[ "$SHELL_BACKUP_CREATED" -eq 1 ] && \
    echo "   - ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptoms: Image pulls fail (timeout), container internet access fails"
