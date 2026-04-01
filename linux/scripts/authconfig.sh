#!/bin/bash
# scripts/authconfig.sh - Remove broken allowedOrgs configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_authconfig.sh:
#   1. Restores ~/.docker/desktop/settings.json from backup (or removes the
#      allowedOrgs key entirely if no backup exists) and restarts Docker Desktop
#
# Note: docker logout cannot be reversed automatically. After running this
# script, sign back in manually via Docker Desktop or docker login.
#
# After repairing the environment, resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootlinuxlab sees no active lab.

set -e

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"

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

echo "Removing broken allowedOrgs configuration..."

# ------------------------------------------------------------------
# Fix ~/.docker/desktop/settings.json
# ------------------------------------------------------------------
echo "Checking Docker Desktop settings file..."

if [ -f "$DESKTOP_SETTINGS" ]; then
    LATEST_BACKUP=$(ls -t "${DESKTOP_SETTINGS}.backup-auth-"* 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$DESKTOP_SETTINGS"
        echo "  Restored from backup: $(basename "$LATEST_BACKUP")"
    else
        # No backup available - remove the allowedOrgs key entirely, which
        # disables org enforcement and allows any authenticated user to proceed.
        echo "  No backup found, removing allowedOrgs key"
        python3 - "$DESKTOP_SETTINGS" << 'EOF'
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

data.pop('allowedOrgs', None)

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF
        echo "  allowedOrgs key removed"
    fi
else
    echo "  Settings file not found - nothing to fix"
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
    echo "  Docker Desktop is running"
fi

echo ""
echo "allowedOrgs configuration cleaned up"
echo ""
echo "NOTE: Credentials were cleared by the break script and cannot be"
echo "automatically restored. Sign back in:"
echo "  docker login"
echo ""

_reset_lab_state
echo "Lab state reset: no active scenario"
