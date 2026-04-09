#!/bin/bash
# all.sh - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Sources lib/fix.sh for individual scenario fix functions, then runs all of
# them in the correct order, performs a single Docker Desktop restart, and
# prints a clear pass/fail summary.

# Source shared fix functions (DESKTOP_SETTINGS, DAEMON_CONFIG, stop_docker_desktop, fix_*)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/fix.sh"

# ===========================================================================
# Shared helpers
# ===========================================================================

# _reset_lab_state - Clear the active scenario from config.json.
# Called once at the end after all fixes have been applied.
_reset_lab_state() {  # local to all.sh - not needed in lib/fix.sh
    local config_file="$HOME/.docker-training-labs/config.json"
    if [ ! -f "$config_file" ]; then
        return
    fi
    local version trainee temp_file
    version=$(grep '"version"' "$config_file" | sed 's/.*"version": *"//;s/".*//' | head -1)
    trainee=$(grep '"trainee_id"' "$config_file" | sed 's/.*"trainee_id": *"//;s/".*//' | head -1)
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

# run_section <label> <function_name>
# Calls the named fix function, tracks pass/fail, never exits early.
run_section() {
    local label="$1"
    local func="$2"
    local exit_code

    echo ""
    echo "--- $label ---"
    $func
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "  -> OK"
    else
        echo "  -> FAILED (exit code $exit_code)"
        failed_steps+=("$label")
    fi
    echo ""
    echo "=========================================="
}

# ===========================================================================
# Main
# ===========================================================================

echo "=========================================="
echo "Restoring ALL Docker Desktop Systems"
echo "=========================================="
echo ""
echo "This will fix:"
echo "  1. Bridge Network"
echo "  2. DNS Resolution"
echo "  3. Proxy Configuration"
echo "  4. Proxy Failure Simulation"
echo "  5. SSO Configuration"
echo "  6. Auth Config Enforcement"
echo "  7. Port Conflicts"
echo ""
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=========================================="

# Tracks which steps failed so we can report clearly at the end.
failed_steps=()

# ------------------------------------------------------------------
# Phase 1: fixes that require Docker to be running.
#
# Bridge and DNS inject iptables rules inside the VM via nsenter, which
# requires a running daemon. Port cleanup uses docker rm. Proxy and
# ProxyFail use the Docker Desktop backend socket API, which also
# requires a running daemon. All five must run before Docker Desktop
# is stopped.
# ------------------------------------------------------------------
run_section "[1/7] Bridge Network"           fix_bridge
run_section "[2/7] DNS Resolution"           fix_dns
run_section "[3/7] Proxy Configuration"      fix_proxy
run_section "[4/7] Proxy Failure Simulation" fix_proxyfail
run_section "[7/7] Port Conflicts"           fix_ports

# ------------------------------------------------------------------
# Phase 2: fixes that do NOT require Docker to be running or stopped.
#
# SSO edits ~/.docker/config.json, which is only read at login time.
# AuthConfig removes registry.json, which is read at startup. Neither
# file is held open by Docker Desktop, so these fixes are safe to run
# regardless of Docker's state.
# ------------------------------------------------------------------
run_section "[5/7] SSO Configuration"        fix_sso
run_section "[6/7] Auth Config Enforcement"  fix_authconfig

# ------------------------------------------------------------------
# Restart Docker Desktop to pick up any residual state changes.
#
# The API-based fixes (proxy, proxyfail) apply changes live, so a
# restart is not strictly needed for those. SSO and AuthConfig changes
# take effect on the next startup. Restarting here ensures everything
# is in a clean, consistent state.
# ------------------------------------------------------------------
echo ""
echo "--- Restarting Docker Desktop ---"
echo ""

stop_docker_desktop

if systemctl --user start docker-desktop 2>/dev/null; then
    echo "  Start signal sent via systemctl"
else
    echo "  Warning: Could not start Docker Desktop via systemctl"
    echo "  Please restart Docker Desktop manually before continuing"
fi

echo "Waiting for Docker Desktop to restart..."
DOCKER_READY=0
for i in $(seq 1 60); do
    if docker info &>/dev/null 2>&1; then
        DOCKER_READY=1
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" -eq 0 ]; then
    echo "  Warning: Docker Desktop did not come back within 120s"
    failed_steps+=("Docker Desktop restart")
else
    echo "  Docker Desktop is running"
    echo ""
    echo "Verifying registry access..."
    if docker pull hello-world > /dev/null 2>&1; then
        echo "  Registry access working"
        docker rmi hello-world > /dev/null 2>&1 || true
    else
        echo "  Registry access not working - check Docker Desktop status"
        failed_steps+=("Registry access verification")
    fi
fi

echo ""
echo "=========================================="

# Clear lab state now that all fixes have been applied.
_reset_lab_state
echo "Lab state reset: no active scenario"

echo ""
echo "=========================================="

if [ ${#failed_steps[@]} -eq 0 ]; then
    echo "All Systems Restored"
    echo "=========================================="
    echo ""
    echo "Docker Desktop has been restarted. Verify everything is working:"
    echo "  docker pull hello-world"
    echo "  docker run --rm alpine:latest ping -c 2 google.com"
    echo ""
    exit 0
else
    echo "Restore completed with errors"
    echo "=========================================="
    echo ""
    echo "The following steps failed:"
    for step in "${failed_steps[@]}"; do
        echo "  - $step"
    done
    echo ""
    echo "Review the output above for details on each failure."
    echo ""
    exit 1
fi
