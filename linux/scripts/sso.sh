#!/bin/bash
# scripts/sso.sh - Remove broken SSO proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_sso.sh:
#   1. Restores ~/.docker/desktop/settings.json or daemon.json from backup
#      (or resets proxy keys to system mode if no backup exists)
#   2. Resets the lab state in ~/.docker-training-labs/config.json
#
# Note: docker logout cannot be reversed automatically. Sign back in
# manually after running this script.

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

echo "Removing broken SSO proxy configuration..."

# ------------------------------------------------------------------
# Fix ~/.docker/desktop/settings.json
# ------------------------------------------------------------------
if [ -f "$DESKTOP_SETTINGS" ]; then
    echo "Checking Docker Desktop settings file..."
    LATEST_BACKUP=$(ls -t "${DESKTOP_SETTINGS}.backup-"* 2>/dev/null | head -1)

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
    if grep -q "192\.0\.2" "$DAEMON_CONFIG" 2>/dev/null; then
        LATEST_BACKUP=$(ls -t "${DAEMON_CONFIG}.backup-"* 2>/dev/null | head -1)
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

echo ""
echo "SSO proxy configuration cleaned up"
echo ""
echo "IMPORTANT:"
echo "  1. Restart Docker Desktop for changes to take effect"
echo "  2. Sign back in: docker login"
echo ""

_reset_lab_state
echo "Lab state reset: no active scenario"
