#!/bin/bash
# all.sh - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Standalone script: all fix logic is inlined. No external fix scripts required.
# Runs every section regardless of individual failures, performs a single
# Docker Desktop restart at the end, then prints a clear pass/fail summary.

# ===========================================================================
# Configuration
# ===========================================================================

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"

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
# Fix functions - one per scenario
# ===========================================================================

# -- [1/7] Bridge Network ----------------------------------------------------
fix_bridge() {
    echo "Restoring Docker bridge network..."

    echo "Removing test containers..."
    docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
    docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

    echo ""
    echo "Restoring iptables rules..."
    docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
        iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
        echo "DROP rule removed"
    ' || echo "  iptables restore failed - the consolidated restart should clear it"

    echo ""
    echo "Verifying network connectivity..."
    if docker run --rm alpine:latest ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        echo "  Internet connectivity working"
    else
        echo "  Internet connectivity still broken"
    fi
}

# -- [2/7] DNS Resolution ----------------------------------------------------
fix_dns() {
    echo "Fixing Docker Desktop DNS..."

    if ! docker info &>/dev/null; then
        echo "Error: Docker Desktop is not running"
        return 1
    fi

    if ! docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c '
            iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true
            iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
        '; then
        echo "Error: Failed to access the Docker VM via nsenter"
        return 1
    fi

    echo ""
    echo "Verifying DNS resolution..."
    if docker pull hello-world > /dev/null 2>&1; then
        echo "  DNS resolution working"
        docker rmi hello-world > /dev/null 2>&1 || true
    else
        echo "  DNS still broken - the consolidated restart should clear this"
    fi
}

# -- [3/7] Proxy Configuration -----------------------------------------------
# On Linux, Docker Desktop uses daemon.json for proxy settings (not
# settings.json), so this function targets that file.
fix_proxy() {
    local latest_backup rc_file
    echo "Removing broken proxy configuration..."

    echo "Checking daemon.json..."
    if [ -f "$DAEMON_CONFIG" ]; then
        if grep -q "192\.0\.2\.1" "$DAEMON_CONFIG" 2>/dev/null; then
            echo "  Found broken proxy config"
            latest_backup=$(ls -t "${DAEMON_CONFIG}.backup"* 2>/dev/null | head -1)
            if [ -n "$latest_backup" ]; then
                cp "$latest_backup" "$DAEMON_CONFIG"
                echo "  Restored from backup: $latest_backup"
            else
                rm "$DAEMON_CONFIG"
                echo "  Removed broken daemon.json (no backup found)"
            fi
        else
            echo "  daemon.json is clean"
        fi
    else
        echo "  No daemon.json found"
    fi

    echo ""
    echo "Checking shell RC files..."
    for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
        if [ -f "$rc_file" ]; then
            if grep -q "BEGIN DOCKER TRAINING LAB PROXY BREAK" "$rc_file" 2>/dev/null; then
                echo "  Found broken proxy in $rc_file"
                sed -i '/BEGIN DOCKER TRAINING LAB PROXY BREAK/,/END DOCKER TRAINING LAB PROXY BREAK/d' "$rc_file"
                echo "  Removed proxy settings from $rc_file"
            fi
        fi
    done

    echo ""
    echo "Proxy configuration cleaned up"
    echo "Run 'fix-docker-proxy' in this terminal to clear any lingering env vars."
}

# -- [4/7] Proxy Failure Simulation ------------------------------------------
fix_proxyfail() {
    local latest_backup
    echo "Removing broken loopback proxy configuration..."

    # Fix settings.json (primary path when Docker Desktop is installed)
    if [ -f "$DESKTOP_SETTINGS" ]; then
        echo "Checking Docker Desktop settings file..."
        latest_backup=$(ls -t "${DESKTOP_SETTINGS}.backup-proxyfail-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$DESKTOP_SETTINGS"
            echo "  Restored from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, resetting proxy keys to system mode"
            python3 - "$DESKTOP_SETTINGS" << 'PYEOF'
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
PYEOF
            echo "  Proxy keys reset to system mode"
        fi
    fi

    # Fix daemon.json (fallback path used if settings.json was absent during break)
    if [ -f "$DAEMON_CONFIG" ]; then
        echo "Checking daemon.json..."
        if grep -q "9753" "$DAEMON_CONFIG" 2>/dev/null; then
            latest_backup=$(ls -t "${DAEMON_CONFIG}.backup-proxyfail-"* 2>/dev/null | head -1)
            if [ -n "$latest_backup" ]; then
                cp "$latest_backup" "$DAEMON_CONFIG"
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
    echo "Proxy failure configuration cleaned up"
}

# -- [5/7] SSO Configuration -------------------------------------------------
fix_sso() {
    local latest_backup
    echo "Removing broken SSO proxy configuration..."

    # Fix settings.json (primary path when Docker Desktop is installed)
    if [ -f "$DESKTOP_SETTINGS" ]; then
        echo "Checking Docker Desktop settings file..."
        latest_backup=$(ls -t "${DESKTOP_SETTINGS}.backup-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$DESKTOP_SETTINGS"
            echo "  Restored from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, resetting proxy keys to system mode"
            python3 - "$DESKTOP_SETTINGS" << 'PYEOF'
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
PYEOF
            echo "  Proxy keys reset to system mode"
        fi
    fi

    # Fix daemon.json (fallback path used if settings.json was absent during break)
    if [ -f "$DAEMON_CONFIG" ]; then
        echo "Checking daemon.json..."
        if grep -q "192\.0\.2" "$DAEMON_CONFIG" 2>/dev/null; then
            latest_backup=$(ls -t "${DAEMON_CONFIG}.backup-"* 2>/dev/null | head -1)
            if [ -n "$latest_backup" ]; then
                cp "$latest_backup" "$DAEMON_CONFIG"
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
    echo "NOTE: Sign back in manually: docker login"
}

# -- [6/7] Auth Config Enforcement -------------------------------------------
# authconfig only uses settings.json on Linux; there is no daemon.json fallback.
fix_authconfig() {
    local latest_backup
    echo "Removing broken allowedOrgs configuration..."

    echo "Checking Docker Desktop settings file..."
    if [ -f "$DESKTOP_SETTINGS" ]; then
        latest_backup=$(ls -t "${DESKTOP_SETTINGS}.backup-auth-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$DESKTOP_SETTINGS"
            echo "  Restored from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, removing allowedOrgs key"
            python3 - "$DESKTOP_SETTINGS" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)
data.pop('allowedOrgs', None)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
            echo "  allowedOrgs key removed"
        fi
    else
        echo "  Settings file not found - nothing to fix"
    fi

    echo ""
    echo "allowedOrgs configuration cleaned up"
    echo "NOTE: Sign back in manually: docker login"
}

# -- [7/7] Port Conflicts ----------------------------------------------------
fix_ports() {
    local pid
    echo "Cleaning up port conflicts..."

    echo "Removing port squatter containers..."
    docker rm -f port-squatter-80   2>/dev/null && echo "  Removed port-squatter-80"   || true
    docker rm -f port-squatter-443  2>/dev/null && echo "  Removed port-squatter-443"  || true
    docker rm -f port-squatter-3306 2>/dev/null && echo "  Removed port-squatter-3306" || true
    docker rm -f background-db      2>/dev/null && echo "  Removed background-db"      || true

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
# Stop Docker Desktop BEFORE writing to settings.json / daemon.json.
#
# Docker flushes its in-memory configuration back to the settings file
# on a clean shutdown. Writing fixes while Docker is running and then
# stopping it gracefully would cause that flush to overwrite the changes.
# Stopping the process first eliminates that race entirely.
# ------------------------------------------------------------------
echo ""
echo "--- Stopping Docker Desktop ---"
echo ""

if systemctl --user stop docker-desktop 2>/dev/null; then
    echo "  Stopped via systemctl"
else
    # systemctl stop failed - fall back to direct process kill.
    echo "  Warning: systemctl stop failed, force killing..."
    pkill -f "docker-desktop" 2>/dev/null || true
    sleep 2
fi

echo "  Docker Desktop stopped"
echo ""
echo "=========================================="

# ------------------------------------------------------------------
# Phase 2: fixes that write to settings.json / daemon.json.
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

if systemctl --user start docker-desktop 2>/dev/null; then
    echo "  Start signal sent via systemctl"
else
    echo "  Warning: Could not start Docker Desktop via systemctl"
    echo "  Please restart Docker Desktop manually before continuing"
fi

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
