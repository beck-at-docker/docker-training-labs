#!/bin/bash
# break_proxy.sh - Corrupts proxy settings on Mac Docker Desktop
#
# On Mac, Docker Desktop ignores daemon.json proxy settings entirely. Proxy
# config is owned by Docker Desktop and lives in settings-store.json under
# ~/Library/Group Containers/group.com.docker/. This script targets that
# file directly, which is the only reliable way to break proxy config from
# a script on Mac.
#
# Two separate mechanisms are used to simulate layered misconfiguration:
#
#   1. settings-store.json: switches proxy mode from "system" to "manual"
#      and sets a non-routable address (192.0.2.1, RFC 5737 TEST-NET) as
#      both the HTTP and HTTPS proxy. Docker Desktop must be restarted to
#      read the change, which this script handles automatically.
#
#   2. Shell RC file (~/.zshrc or ~/.bash_profile): sets HTTP_PROXY and
#      HTTPS_PROXY environment variables that conflict with any valid proxy
#      config once the terminal is reloaded. Wrapped in sentinel markers
#      for clean programmatic removal.
#
# Both files are backed up with a timestamp before modification so nothing
# is permanently lost.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before we touch anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Verify the settings store exists - if it doesn't, Docker Desktop hasn't
# been fully initialised and we can't proceed safely
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
# Method 1: Corrupt the Docker Desktop settings store
#
# Python3 is used to merge the proxy keys into the existing JSON rather
# than replacing the whole file. Replacing the whole file risks wiping
# out settings (snapshotter choice, feature flags, etc.) that affect
# whether Docker Desktop starts cleanly.
#
# Keys written:
#   ProxyHTTPMode / ContainersProxyHTTPMode - switch from "system" to "manual"
#   ProxyHTTP / ProxyHTTPS                  - daemon-level bogus proxy
#   ContainersProxyHTTP / ContainersProxyHTTPS - container-level bogus proxy
#   ProxyExclude / ContainersProxyExclude   - empty, so nothing bypasses it
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"

python3 - "$SETTINGS_STORE" << 'EOF'
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

bogus_proxy = "http://192.0.2.1:8080"

data['ProxyHTTPMode']            = 'manual'
data['ProxyHTTP']                = bogus_proxy
data['ProxyHTTPS']               = bogus_proxy
data['ProxyExclude']             = ''
data['ContainersProxyHTTPMode']  = 'manual'
data['ContainersProxyHTTP']      = bogus_proxy
data['ContainersProxyHTTPS']     = bogus_proxy
data['ContainersProxyExclude']   = ''

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF

echo "  Settings store updated"

# ------------------------------------------------------------------
# Method 2: Corrupt shell RC file with bogus proxy env vars
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
# Relaunch Docker Desktop so it starts fresh with the broken settings.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply proxy settings..."

# Relaunch Docker Desktop
open /Applications/Docker.app

# Poll in two stages:
#
#   Stage 1 - wait for the daemon to be up (docker info succeeds)
#   Stage 2 - wait for the proxy to be active (docker info reports 192.0.2.1)
#
# Stage 2 is necessary because Docker Desktop accepts connections before it
# has fully applied settings-store.json. Without it, --check can run before
# the proxy is live and see pulls succeeding when they should be failing.
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
else
    echo "  Daemon is up, waiting for proxy settings to take effect..."
    PROXY_ACTIVE=0
    for i in $(seq 1 15); do
        if docker info 2>/dev/null | grep -q "192.0.2.1"; then
            PROXY_ACTIVE=1
            break
        fi
        sleep 2
    done

    if [ "$PROXY_ACTIVE" -eq 0 ]; then
        echo "  Warning: Proxy settings did not appear in docker info within 30s"
        echo "  You may need to wait a moment before the break is fully active"
    fi
fi

echo ""
echo "Docker Desktop broken"
echo "Backups saved:"
echo "  ${SETTINGS_STORE}.backup-proxy-${BACKUP_TIMESTAMP}"
echo "  ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptoms: Image pulls fail, container internet access fails"
