#!/bin/bash
# lib/fix.sh - Scenario fix functions for Docker Desktop Training Labs
#
# This file is a shared library. It is sourced by:
#   - troubleshootmaclab  (via fix_current_lab, called from abandon_lab)
#   - scenarios/all.sh    (Fix All trainer tool)
#
# Each fix_<scenario> function is idempotent: running it on an already-fixed
# environment is safe and produces no harmful side effects.
#
# Scenarios that write to settings-store.json (PROXY, PROXYFAIL, SSO,
# AUTHCONFIG) MUST be applied after Docker Desktop is stopped. Docker flushes
# its in-memory config back to settings-store.json on a clean shutdown, which
# would overwrite any changes written while the daemon was running.
# Call stop_docker_desktop before invoking any of those four functions.
#
# Scenarios that operate via live iptables or container removal (DNS, BRIDGE,
# PORT) require Docker to be running and do not need a restart to take effect.

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

# stop_docker_desktop - Quit Docker Desktop and wait for the process to exit.
#
# Sends a graceful AppleScript quit first, then polls for up to ~15 seconds.
# Force-kills if the graceful shutdown has not completed within that window.
# A broken proxy, bridge, or other degraded state can cause shutdown to hang
# indefinitely, which is why the force-kill fallback is necessary.
stop_docker_desktop() {
    echo "Stopping Docker Desktop..."
    osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true

    for i in $(seq 1 15); do
        if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if pgrep -x "Docker Desktop" > /dev/null 2>&1; then
        echo "  Force killing Docker Desktop (graceful quit timed out)..."
        killall -9 "Docker Desktop" 2>/dev/null || true
        sleep 2
    fi

    echo "  Docker Desktop stopped"
}

# fix_bridge - Restore the Docker bridge network.
#
# Removes the lab's test containers and the iptables DROP rule injected into
# the Docker VM by break_bridge.sh. Requires a running Docker daemon.
fix_bridge() {
    echo "Restoring Docker bridge network..."

    echo "Removing test containers..."
    docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
    docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

    echo ""
    echo "Restoring iptables rules..."
    docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c \
            'iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
             echo "DROP rule removed"' \
    || echo "  iptables restore failed - a Docker Desktop restart should clear it"

    echo ""
    echo "Verifying network connectivity..."
    if docker run --rm alpine:latest ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        echo "  Internet connectivity restored"
    else
        echo "  Internet connectivity still broken"
    fi
}

# fix_dns - Remove the iptables DNS-block rules from inside the Docker VM.
#
# break_dns.sh injects DROP rules for UDP/TCP port 53 in the VM's OUTPUT
# chain. This function removes them via nsenter. Requires a running daemon.
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
        echo "  DNS resolution restored"
        docker rmi hello-world > /dev/null 2>&1 || true
    else
        echo "  DNS still broken - a Docker Desktop restart should clear this"
    fi
}

# fix_proxy - Remove the bogus manual proxy from settings-store.json and RC files.
#
# Restores from a scenario-specific backup if one exists; otherwise resets
# proxy keys to system mode directly. Also strips the break-sentinel block
# from shell RC files that break_proxy.sh may have injected.
#
# MUST be called after stop_docker_desktop.
fix_proxy() {
    local latest_backup rc_file
    echo "Removing broken proxy configuration..."

    echo "Checking Docker Desktop settings store..."
    if [ -f "$SETTINGS_STORE" ]; then
        latest_backup=$(ls -t "${SETTINGS_STORE}.backup-proxy-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_STORE"
            echo "  Restored settings store from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, resetting proxy keys to system mode"
            python3 - "$SETTINGS_STORE" << 'PYEOF'
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
    else
        echo "  Settings store not found - nothing to fix"
    fi

    echo ""
    echo "Checking shell RC files..."
    for rc_file in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
        if [ -f "$rc_file" ]; then
            if grep -q "BEGIN DOCKER TRAINING LAB PROXY BREAK" "$rc_file" 2>/dev/null; then
                echo "  Found broken proxy block in $rc_file"
                sed -i '' '/BEGIN DOCKER TRAINING LAB PROXY BREAK/,/END DOCKER TRAINING LAB PROXY BREAK/d' "$rc_file"
                echo "  Removed proxy settings from $rc_file"
            fi
        fi
    done

    echo ""
    echo "Proxy configuration cleaned up"
    echo "Run 'fix-docker-proxy' in this terminal to clear any lingering env vars."
}

# fix_proxyfail - Remove the loopback proxy address from settings-store.json.
#
# break_proxyfail.sh sets ProxyHTTP/HTTPS to 127.0.0.1:9753 which causes an
# immediate connection-refused error on every pull. Restores from backup or
# resets to system mode.
#
# MUST be called after stop_docker_desktop.
fix_proxyfail() {
    local latest_backup
    echo "Removing broken loopback proxy configuration..."

    echo "Checking Docker Desktop settings store..."
    if [ -f "$SETTINGS_STORE" ]; then
        latest_backup=$(ls -t "${SETTINGS_STORE}.backup-proxyfail-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_STORE"
            echo "  Restored settings store from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, resetting proxy keys to system mode"
            python3 - "$SETTINGS_STORE" << 'PYEOF'
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
    else
        echo "  Settings store not found - nothing to fix"
    fi

    echo ""
    echo "Proxy failure configuration cleaned up"
}

# fix_sso - Remove the asymmetric ProxyExclude from settings-store.json.
#
# break_sso.sh sets a ProxyExclude list that covers the registry but not the
# SSO login endpoints, causing auth to fail while pulls still work. Restores
# from backup or resets proxy keys to system mode.
#
# MUST be called after stop_docker_desktop.
fix_sso() {
    local latest_backup
    echo "Removing broken SSO proxy configuration..."

    echo "Checking Docker Desktop settings store..."
    if [ -f "$SETTINGS_STORE" ]; then
        latest_backup=$(ls -t "${SETTINGS_STORE}.backup-sso-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_STORE"
            echo "  Restored settings store from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, resetting proxy keys to system mode"
            python3 - "$SETTINGS_STORE" << 'PYEOF'
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
    else
        echo "  Settings store not found - nothing to fix"
    fi

    echo ""
    echo "SSO proxy configuration cleaned up"
    echo "NOTE: Sign back in manually after Docker Desktop restarts: docker login"
}

# fix_authconfig - Remove the corrupt allowedOrgs value from settings-store.json.
#
# break_authconfig.sh sets allowedOrgs to a URL-format value instead of a
# plain org slug, causing the sign-in loop. Restores from backup or removes
# the allowedOrgs key entirely.
#
# MUST be called after stop_docker_desktop.
fix_authconfig() {
    local latest_backup
    echo "Removing broken allowedOrgs configuration..."

    echo "Checking Docker Desktop settings store..."
    if [ -f "$SETTINGS_STORE" ]; then
        latest_backup=$(ls -t "${SETTINGS_STORE}.backup-auth-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_STORE"
            echo "  Restored settings store from backup: $(basename "$latest_backup")"
        else
            echo "  No backup found, removing allowedOrgs key"
            python3 - "$SETTINGS_STORE" << 'PYEOF'
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
        echo "  Settings store not found - nothing to fix"
    fi

    echo ""
    echo "allowedOrgs configuration cleaned up"
    echo "NOTE: Sign back in manually after Docker Desktop restarts: docker login"
}

# fix_ports - Remove port-squatter containers and background HTTP processes.
#
# break_ports.sh starts several containers and a Python HTTP server that hold
# common ports (80, 443, 3306, 5432, 8080). This removes them so the ports
# are available again. Requires a running Docker daemon.
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
    pkill -f "python3 -m http.server 8080" 2>/dev/null && echo "  Killed any remaining HTTP servers" || true

    echo ""
    echo "Port cleanup complete"
}
