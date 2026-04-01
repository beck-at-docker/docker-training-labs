#!/bin/bash
# scripts/proxyfail.sh - Remove broken loopback proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_proxyfail.sh:
#   1. Restores ~/.docker/desktop/settings.json from backup (or resets proxy
#      keys to system mode if no backup exists)
#   2. Falls back to daemon.json cleanup if settings.json was not present
#      during the break
#   3. Restarts Docker Desktop and verifies registry access
#
# After repairing the environment, resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootlinuxlab sees no active lab.

set -e

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"

# Reset the training lab state file so the CLI sees no active scenario.
# Mirrors the logic in lib/state.sh without requiring it to be sourced.
_reset_lab_state() {
    local config_file="$HOME/.docker-training-labs/config.json"
    if [ ! -f "$config_file" ]; then
        return
    fi
    local version
    local trainee
    version=$(grep '"version"' "$config_file" | sed 's/.*"version": *"//;s/".*//' | head -1)
    trainee=$(grep '"trainee_id"' "$config_file" | sed 's/.*"trainee_id": *"//;s/".*//' | head -1)
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << EOF
{
  "version": "${version:-1.0.0}",
  "trainee_id": "${trainee:-$USER}",
  "current_scenario": null,
  "scenario_start_time": null
}
EOF
    mv "$temp_file" "$config_file"
}

echo "Removing broken loopback proxy configuration..."

# ------------------------------------------------------------------
# Fix ~/.docker/desktop/settings.json
# ------------------------------------------------------------------
if [ -f "$DESKTOP_SETTINGS" ]; then
    echo "Checking Docker Desktop settings file..."
    LATEST_BACKUP=$(ls -t "${DESKTOP_SETTINGS}.backup-proxyfail-"* 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$DESKTOP_SETTINGS"
        echo "  Restored from backup: $(basename "$LATEST_BACKUP")"
    else
        echo "  No backup found, resetting proxy keys to system mode"
        python3 - "$DESKTOP_SETTINGS" << 'EOF'
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

for key in ['ProxyHTTP', 'ProxyHTTPS', 'ProxyExclude',
            'ContainersProxyHTTP', 'ContainersProxyHTTPS', 'ContainersProxyExclude']:
    data.pop(key, None)

data['ProxyHTTPMode']           = 'system'
data['ContainersProxyHTTPMode'] = 'system'

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF
        echo "  Proxy keys reset to system mode"
    fi
fi

# ------------------------------------------------------------------
# Fix daemon.json (fallback path used if settings.json didn't exist)
# ------------------------------------------------------------------
if [ -f "$DAEMON_CONFIG" ]; then
    echo "Checking daemon.json..."
    if grep -q "9753" "$DAEMON_CONFIG" 2>/dev/null; then
        LATEST_BACKUP=$(ls -t "${DAEMON_CONFIG}.backup-proxyfail-"* 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$DAEMON_CONFIG"
            echo "  Restored daemon.json from backup"
        else
            rm "$DAEMON_CONFIG"
            echo "  Removed broken daemon.json (no backup found)"
        fi
    else
        echo "  daemon.json is clean"
    fi
fi

# ------------------------------------------------------------------
# Restart Docker Desktop to apply the restored settings
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply restored settings..."

if systemctl --user restart docker-desktop 2>/dev/null; then
    echo "  Restart signal sent via systemctl"
else
    pkill -f "docker-desktop" 2>/dev/null || true
    echo "  Warning: Could not restart Docker Desktop automatically via systemctl"
    echo "  Please restart Docker Desktop manually"
fi

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
else
    echo ""
    echo "Verifying registry access..."
    if docker pull hello-world > /dev/null 2>&1; then
        echo "  Registry access working"
        docker rmi hello-world > /dev/null 2>&1 || true
    else
        echo "  Registry access not working - check Docker Desktop status"
    fi
fi

echo ""
echo "Proxy configuration cleaned up"
echo ""

_reset_lab_state
echo "Lab state reset: no active scenario"
