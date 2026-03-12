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
#                                 → connection timeout after a wait
#   This lab (127.0.0.1:9753):    packets delivered, port not listening
#                                 → immediate "connection refused" error
#
# Port 9753 is chosen because it is above the privileged range (no sudo
# required to inspect it), is not a commonly used application port, and is
# very unlikely to be occupied on a typical developer workstation.
#
# This lab modifies settings-store.json only. It intentionally does not
# corrupt the shell RC file; the diagnostic focus is on reading Docker
# Desktop's proxy configuration directly from the settings store.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BROKEN_PROXY="http://127.0.0.1:9753"

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Verify the settings store exists
if [ ! -f "$SETTINGS_STORE" ]; then
    echo "Error: Docker Desktop settings store not found at:"
    echo "  $SETTINGS_STORE"
    exit 1
fi

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE modifying settings-store.json.
#
# Docker Desktop persists its in-memory configuration back to
# settings-store.json on clean shutdown. Writing the broken settings
# first and then quitting would cause the graceful shutdown to
# overwrite our changes. Stopping the process first prevents that race.
# ------------------------------------------------------------------
echo ""
echo "Stopping Docker Desktop before modifying settings..."

osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true

# Wait for the Docker Desktop process to exit
for i in $(seq 1 15); do
    if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ------------------------------------------------------------------
# Corrupt the settings store with a loopback proxy address.
#
# 127.0.0.1:9753 routes to the local machine's TCP stack, which responds
# immediately with "connection refused" because nothing is listening on
# that port. Both daemon-level and container-level proxy keys are written
# so both docker pull and container internet access fail consistently.
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-${BACKUP_TIMESTAMP}"

python3 - "$SETTINGS_STORE" "$BROKEN_PROXY" << 'EOF'
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

echo "  Settings store updated"

# ------------------------------------------------------------------
# Relaunch Docker Desktop so it starts fresh with the broken settings.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply proxy settings..."

open /Applications/Docker.app

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
echo "Backup saved: ${SETTINGS_STORE}.backup-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptoms: Image pulls fail with connection refused; container internet access fails"
