#!/bin/bash
# ports.sh - Clean up port squatter containers and processes
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

echo "Cleaning up port conflicts..."

# Remove all port squatter containers
echo "Removing port squatter containers..."
docker rm -f port-squatter-80  2>/dev/null && echo "  Removed port-squatter-80"  || true
docker rm -f port-squatter-443 2>/dev/null && echo "  Removed port-squatter-443" || true
docker rm -f port-squatter-3306 2>/dev/null && echo "  Removed port-squatter-3306" || true
docker rm -f background-db     2>/dev/null && echo "  Removed background-db"     || true

# Kill Python HTTP server
echo ""
echo "Killing Python HTTP server on port 8080..."
if [ -f /tmp/port_squatter_8080.pid ]; then
    pid=$(cat /tmp/port_squatter_8080.pid)
    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid" 2>/dev/null && echo "  Killed process $pid" || true
    fi
    rm -f /tmp/port_squatter_8080.pid
fi

# Also kill by name in case the PID file is stale or missing
pkill -f "python3 -m http.server 8080" 2>/dev/null && echo "  Killed any remaining HTTP servers" || true

echo ""
echo "Port cleanup complete"

# Reset the lab state last, after the environment is repaired.
_reset_lab_state
echo "Lab state reset: no active scenario"
