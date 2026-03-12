#!/bin/bash
# sso.sh - Remove broken SSO proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_sso.sh:
#   1. Restores settings-store.json from backup (or resets proxy keys to
#      "system" mode if no backup exists) and restarts Docker Desktop
#
# Note: docker logout cannot be reversed automatically - the trainee's
# credentials were cleared to simulate the signed-out state. After running
# this script, sign back in manually via Docker Desktop or docker login.
#
# After repairing the environment, resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootmaclab sees no active lab.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

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

echo "Removing broken SSO proxy configuration..."

# ------------------------------------------------------------------
# Fix settings-store.json
# ------------------------------------------------------------------
echo "Checking Docker Desktop settings store..."

if [ -f "$SETTINGS_STORE" ]; then
    LATEST_BACKUP=$(ls -t "${SETTINGS_STORE}.backup-"* 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$SETTINGS_STORE"
        echo "  Restored settings store from backup: $(basename "$LATEST_BACKUP")"
    else
        echo "  No backup found, resetting proxy keys to system mode"
        python3 - "$SETTINGS_STORE" << 'EOF'
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
else
    echo "  Settings store not found - nothing to fix"
fi

# ------------------------------------------------------------------
# Restart Docker Desktop to apply the restored settings
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply restored settings..."

osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

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
else
    echo "  Docker Desktop is running"
fi

echo ""
echo "SSO proxy configuration cleaned up"
echo ""
echo "NOTE: Credentials were cleared by the break script and cannot be"
echo "automatically restored. Sign back in via Docker Desktop or:"
echo "  docker login"
echo ""

_reset_lab_state
echo "Lab state reset: no active scenario"
