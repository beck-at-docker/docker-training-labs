#!/bin/bash
# authconfig.sh - Remove broken allowedOrgs configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_authconfig.sh:
#   1. Restores settings-store.json from backup (or removes the allowedOrgs
#      key entirely if no backup exists) and restarts Docker Desktop
#
# Note: docker logout cannot be reversed automatically. After running this
# script, sign back in manually via Docker Desktop or docker login.
#
# After repairing the environment, resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootmaclab sees no active lab.

set -e

# When called with --no-restart, skip the Docker Desktop restart cycle.
# all.sh uses this flag so it can perform a single consolidated restart
# after all fix scripts have made their settings-store.json changes.
NO_RESTART=0
if [ "${1:-}" = "--no-restart" ]; then
    NO_RESTART=1
fi

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

echo "Removing broken allowedOrgs configuration..."

# ------------------------------------------------------------------
# Fix settings-store.json
# ------------------------------------------------------------------
echo "Checking Docker Desktop settings store..."

if [ -f "$SETTINGS_STORE" ]; then
    LATEST_BACKUP=$(ls -t "${SETTINGS_STORE}.backup-auth-"* 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$SETTINGS_STORE"
        echo "  Restored settings store from backup: $(basename "$LATEST_BACKUP")"
    else
        # No backup available - remove the allowedOrgs key entirely, which
        # disables org enforcement and allows any authenticated user to proceed.
        echo "  No backup found, removing allowedOrgs key from settings store"
        python3 - "$SETTINGS_STORE" << 'EOF'
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
    echo "  Settings store not found - nothing to fix"
fi

if [ "$NO_RESTART" -eq 0 ]; then
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
else
    echo ""
    echo "Skipping Docker Desktop restart (will be restarted by caller)."
fi

echo ""
echo "allowedOrgs configuration cleaned up"
echo ""
echo "NOTE: Credentials were cleared by the break script and cannot be"
echo "automatically restored. Sign back in via Docker Desktop or:"
echo "  docker login"
echo ""

# Reset the lab state last, after the environment is repaired.
_reset_lab_state
echo "Lab state reset: no active scenario"
