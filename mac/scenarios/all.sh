#!/bin/bash
# all.sh - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Sources lib/fix.sh for individual scenario fix functions, then runs all of
# them in the correct order, performs a single Docker Desktop restart, and
# prints a clear pass/fail summary.

# Source shared fix functions (SETTINGS_STORE, stop_docker_desktop, fix_*)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/fix.sh"

# ===========================================================================
# Shared helpers
# ===========================================================================

# _reset_lab_state - Clear the active scenario from config.json.
# Called once at the end after all fixes have been applied.

_reset_lab_state() {
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
# requires a running daemon. Port cleanup uses docker rm. All three must
# run before Docker Desktop is stopped.
# ------------------------------------------------------------------
run_section "[1/7] Bridge Network" fix_bridge
run_section "[2/7] DNS Resolution" fix_dns
run_section "[7/7] Port Conflicts" fix_ports

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE writing to settings-store.json.
#
# Docker flushes its in-memory configuration back to settings-store.json
# on a clean shutdown. Writing fixes while Docker is running and then
# quitting gracefully would cause that flush to overwrite the changes.
# Stopping the process first eliminates that race entirely.
# ------------------------------------------------------------------
echo ""
echo "--- Stopping Docker Desktop ---"
echo ""

stop_docker_desktop

echo ""
echo "=========================================="

# ------------------------------------------------------------------
# Phase 2: fixes that write to settings-store.json.
#
# Docker Desktop is stopped so these writes are safe - there is no
# running process to flush in-memory state back over the changes.
# ------------------------------------------------------------------
run_section "[3/7] Proxy Configuration"      fix_proxy
run_section "[4/7] Proxy Failure Simulation" fix_proxyfail
run_section "[5/7] SSO Configuration"        fix_sso
run_section "[6/7] Auth Config Enforcement"  fix_authconfig

# ------------------------------------------------------------------
# Relaunch Docker Desktop with the corrected settings.
# ------------------------------------------------------------------
echo ""
echo "--- Restarting Docker Desktop ---"
echo ""

open /Applications/Docker.app

echo "Docker Desktop must be started manually..."
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
    echo "  docker run -p 8080:80 nginx:alpine"
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
