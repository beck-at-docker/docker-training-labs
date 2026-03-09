#!/bin/bash
# fix_dns.sh - Restore Docker daemon DNS resolution in Docker Desktop
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# The DNS break injects two iptables DROP rules for port 53 into the Docker
# Desktop VM's OUTPUT chain via nsenter. This script removes those rules
# using the same mechanism.
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

echo "Fixing Docker Desktop DNS..."

# Verify Docker Desktop is running before attempting anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Remove the DROP rules for port 53 (UDP and TCP) from the VM's OUTPUT chain.
# -D deletes the first matching rule; run once per protocol to match the two
# rules injected by break_dns.sh.
if ! docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c '
        iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true
        iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
    '; then
    echo "Error: Failed to access the Docker VM via nsenter"
    exit 1
fi

# Verify the fix
echo ""
echo "Verifying DNS resolution..."
if docker pull hello-world > /dev/null 2>&1; then
    echo "DNS resolution working"
else
    echo "DNS still broken - may need Docker Desktop restart"
fi

# Reset the lab state last, after the environment is repaired.
_reset_lab_state
echo "Lab state reset: no active scenario"
