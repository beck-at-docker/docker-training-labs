#!/bin/bash
# bridge.sh - Restore Docker bridge network
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# After repairing the environment, this script also resets the lab state in
# ~/.docker-training-labs/config.json so troubleshootmaclab sees no active lab.

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

# Remove conflicting networks
echo "Removing conflicting networks..."
docker network rm fake-bridge-1 2>/dev/null && echo "  Removed fake-bridge-1" || true
docker network rm fake-bridge-2 2>/dev/null && echo "  Removed fake-bridge-2" || true

# Remove test containers
echo ""
echo "Removing test containers..."
docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

# Restore iptables rules in the Docker VM
echo ""
echo "Restoring iptables rules..."
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    # Remove the blocking DROP rule
    iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
    
    # Restore Docker FORWARD chain rules if missing
    # Check if DOCKER chain exists
    if ! iptables -L DOCKER -n > /dev/null 2>&1; then
        iptables -N DOCKER 2>/dev/null || true
    fi
    
    # Re-add standard Docker rules if missing
    iptables -C FORWARD -o docker0 -j DOCKER 2>/dev/null || \
        iptables -A FORWARD -o docker0 -j DOCKER
    
    iptables -C FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    iptables -C FORWARD -i docker0 ! -o docker0 -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i docker0 ! -o docker0 -j ACCEPT
    
    iptables -C FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT
    
    echo "iptables rules restored"
' || echo "  Manual iptables restore failed, restarting Docker Desktop recommended"

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
echo "  1. Click Docker whale icon in menu bar"
echo "  2. Select 'Restart'"

# Reset the lab state last, after the environment is repaired.
_reset_lab_state
echo "Lab state reset: no active scenario"
