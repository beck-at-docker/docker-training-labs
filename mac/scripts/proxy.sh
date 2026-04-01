#!/bin/bash
# proxy.sh - Remove broken proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_proxy.sh:
#   1. Restores settings-store.json from backup (or resets proxy keys to
#      "system" mode if no backup exists) and restarts Docker Desktop
#   2. Removes the bogus proxy exports from the shell RC file
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

echo "Removing broken proxy configuration..."

# ------------------------------------------------------------------
# Fix settings-store.json
# ------------------------------------------------------------------
echo "Checking Docker Desktop settings store..."

if [ -f "$SETTINGS_STORE" ]; then
    # Check for the most recent backup
    LATEST_BACKUP=$(ls -t "${SETTINGS_STORE}.backup-proxy-"* 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$SETTINGS_STORE"
        echo "  Restored settings store from backup: $(basename "$LATEST_BACKUP")"
    else
        # No backup - reset proxy keys to system mode via python3
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
# Fix shell RC files
# ------------------------------------------------------------------
echo ""
echo "Checking shell RC files..."

for rc_file in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    if [ -f "$rc_file" ]; then
        if grep -q "BEGIN DOCKER TRAINING LAB PROXY BREAK" "$rc_file" 2>/dev/null; then
            echo "  Found broken proxy in $rc_file"
            # macOS sed requires the empty-string argument after -i
            sed -i '' '/BEGIN DOCKER TRAINING LAB PROXY BREAK/,/END DOCKER TRAINING LAB PROXY BREAK/d' "$rc_file"
            echo "  Removed proxy settings from $rc_file"
        fi
    fi
done

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
        # Verify registry access is restored
        echo ""
        echo "Verifying registry access..."
        if docker pull hello-world > /dev/null 2>&1; then
            echo "  Registry access working"
            docker rmi hello-world > /dev/null 2>&1 || true
        else
            echo "  Registry access not working - check Docker Desktop status"
        fi
    fi
else
    echo ""
    echo "Skipping Docker Desktop restart (will be restarted by caller)."
fi

echo ""
echo "Proxy configuration cleaned up"
echo ""
echo "Run 'fix-docker-proxy' to clear proxy vars in this terminal."
echo ""

# Reset the lab state last, after the environment is repaired.
_reset_lab_state
echo "Lab state reset: no active scenario"
