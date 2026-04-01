#!/bin/bash
# bridge.sh - Restore Docker bridge network
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# After repairing the environment, this script also resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootlinuxlab sees no active lab.

set -e

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

echo "Restoring Docker bridge network..."

# Remove test containers
echo "Removing test containers..."
docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

# Remove the DROP rule injected by break_bridge.sh. The Docker chain rules
# are untouched by the break and do not need to be restored.
echo ""
echo "Restoring iptables rules..."
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
    echo "DROP rule removed"
' || echo "  iptables restore failed - restarting Docker Desktop is recommended"

# Verify the fix
echo ""
echo "Verifying network connectivity..."
if docker run --rm alpine:latest ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    echo "  Internet connectivity working"
else
    echo "  Internet connectivity still broken"
fi

if docker run --rm alpine:latest ping -c 2 google.com > /dev/null 2>&1; then
    echo "  DNS resolution working"
else
    echo "  DNS still broken"
fi

echo ""
echo "Bridge network restoration complete"
echo ""
echo "If issues persist, restart Docker Desktop:"
echo "  systemctl --user restart docker-desktop"

_reset_lab_state
echo "Lab state reset: no active scenario"
