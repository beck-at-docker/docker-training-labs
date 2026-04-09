#!/bin/bash
# scenarios/break_proxyfail.sh - Simulates a proxy misconfiguration where Docker Desktop
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
#                                 → connection timeout after a wait
#   This lab (127.0.0.1:9753):    packets delivered, port not listening
#                                 → immediate "connection refused" error
#
# Port 9753 is chosen because it is above the privileged range (no sudo
# required to inspect it), is not a commonly used application port, and is
# very unlikely to be occupied on a typical developer workstation.
#
# On Linux, Docker Desktop stores its GUI-level proxy config in:
#   ~/.docker/desktop/settings-store.json
#
# If that file does not exist (older Docker Desktop or different installation),
# this script falls back to ~/.docker/daemon.json.

set -e

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BROKEN_PROXY="http://127.0.0.1:9753"

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE modifying settings files.
#
# Docker Desktop persists its in-memory configuration back to
# settings.json on clean shutdown. Writing the broken settings first
# and then quitting would cause the graceful shutdown to overwrite our
# changes. Stopping the process first prevents that race.
# ------------------------------------------------------------------
echo ""
echo "Stopping Docker Desktop before modifying settings..."

if systemctl --user stop docker-desktop 2>/dev/null; then
    echo "  Stopped via systemctl"
else
    pkill -f "docker-desktop" 2>/dev/null || true
    echo "  Stopped via pkill"
fi

# Wait for the Docker Desktop process to exit
for i in $(seq 1 15); do
    if ! pgrep -f "docker-desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ------------------------------------------------------------------
# Corrupt the proxy config with a loopback proxy address.
#
# 127.0.0.1:9753 routes to the local machine's TCP stack, which responds
# immediately with "connection refused" because nothing is listening on
# that port. Both daemon-level and container-level proxy keys are written
# so both docker pull and container internet access fail consistently.
#
# Prefer ~/.docker/desktop/settings.json; fall back to daemon.json.
# ------------------------------------------------------------------
if [ -f "$DESKTOP_SETTINGS" ]; then
    cp "$DESKTOP_SETTINGS" "${DESKTOP_SETTINGS}.backup-proxyfail-${BACKUP_TIMESTAMP}"

    python3 - "$DESKTOP_SETTINGS" "$BROKEN_PROXY" << 'EOF'
import json, sys

path  = sys.argv[1]
proxy = sys.argv[2]

with open(path, 'r') as f:
    data = json.load(f)

data['ProxyHTTPMode']            = 'manual'
data['ProxyHTTP']                = proxy
data['ProxyHTTPS']               = proxy
data['ProxyExclude']             = ''
data['ContainersProxyHTTPMode']  = 'manual'
data['ContainersProxyHTTP']      = proxy
data['ContainersProxyHTTPS']     = proxy
data['ContainersProxyExclude']   = ''

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF
    echo "  Docker Desktop settings updated (${DESKTOP_SETTINGS})"
    BACKUP_PATH="${DESKTOP_SETTINGS}.backup-proxyfail-${BACKUP_TIMESTAMP}"

else
    # Fallback: write directly to daemon.json. This controls the Docker daemon's
    # proxy, not Docker Desktop's GUI layer, so symptoms are the same but the
    # diagnostic path (finding the config file) differs slightly.
    echo "  ~/.docker/desktop/settings.json not found - using daemon.json fallback"
    mkdir -p "$HOME/.docker"

    if [ -f "$DAEMON_CONFIG" ]; then
        cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup-proxyfail-${BACKUP_TIMESTAMP}"
    fi

    cat > "$DAEMON_CONFIG" << EOF
{
  "proxies": {
    "http-proxy": "$BROKEN_PROXY",
    "https-proxy": "$BROKEN_PROXY"
  }
}
EOF
    echo "  daemon.json updated"
    BACKUP_PATH="${DAEMON_CONFIG}.backup-proxyfail-${BACKUP_TIMESTAMP}"
fi

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply proxy settings..."

if systemctl --user start docker-desktop 2>/dev/null; then
    echo "  Restart signal sent via systemctl"
else
    echo "  Warning: Could not restart Docker Desktop automatically via systemctl"
    echo "  Please restart Docker Desktop manually before starting the lab"
fi

echo "Docker Desktop must be started manually..."
echo "  Waiting for Docker Desktop to restart..."
DOCKER_READY=0
for i in $(seq 1 30); do
    if docker info &>/dev/null 2>&1; then
        DOCKER_READY=1
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" -eq 0 ]; then
    echo "  Warning: Docker Desktop did not come back within 60s"
    echo "  You may need to wait a moment before the break is fully active"
fi

echo ""
echo "Docker Desktop broken"
echo "Backup saved: ${BACKUP_PATH}"
echo ""
echo "Symptoms: Image pulls fail with connection refused; container internet access fails"
