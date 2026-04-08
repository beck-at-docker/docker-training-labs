#!/bin/bash
# lib/fix.sh - Scenario fix functions for Docker Desktop Training Labs (Linux)
#
# This file is a shared library. It is sourced by:
#   - troubleshootlinuxlab  (via fix_current_lab, called from abandon_lab)
#   - scenarios/all.sh      (Fix All trainer tool)
#
# Each fix_<scenario> function is idempotent: running it on an already-fixed
# environment is safe and produces no harmful side effects.
#
# Scenarios that write to settings.json or daemon.json (PROXY, PROXYFAIL,
# AUTHCONFIG) MUST be applied after Docker Desktop is stopped. Docker flushes
# its in-memory configuration back to the settings file on a clean shutdown,
# which would overwrite any changes written while the daemon was running.
# Call stop_docker_desktop before invoking any of those three functions.
#
# SSO is the exception: its fix operates on ~/.docker/config.json, which is
# only read at login time and does not require the daemon to be stopped.
#
# Scenarios that operate via live iptables or container removal (DNS, PORT)
# require Docker to be running and do not need a restart to take effect.
#
# BRIDGE requires Docker to be running (for nsenter), but DOES trigger a full
# restart afterward to ensure Docker rebuilds its forwarding chains cleanly.

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"

# stop_docker_desktop - Stop Docker Desktop and wait for the process to exit.
#
# Tries a clean systemctl stop first. Falls back to pkill if that fails, which
# can happen when Docker Desktop is in a degraded state.
stop_docker_desktop() {
    echo "Stopping Docker Desktop..."
    if systemctl --user stop docker-desktop 2>/dev/null; then
        echo "  Stopped via systemctl"
    else
        echo "  Warning: systemctl stop failed, force killing..."
        pkill -f "docker-desktop" 2>/dev/null || true
        sleep 2
    fi
    echo "  Docker Desktop stopped"
}

# _drain_bridge_drop_rules - Remove all matching DROP rules from FORWARD.
#
# Runs inside a single nsenter shell to avoid spinning up a new container
# for each rule. Called both before and after the Docker Desktop restart:
# before to clean up the injected rule while Docker is still running,
# after to handle the case where the Linux Docker Desktop VM persists across
# a daemon-only restart (i.e. systemctl stop/start restarts the daemon
# service but leaves the underlying QEMU VM running with its iptables intact).
_drain_bridge_drop_rules() {
    local removed_count
    removed_count=$(
        docker run --rm --privileged --pid=host alpine:latest \
            nsenter -t 1 -m -u -n -i sh -c '
                count=0
                while iptables -D FORWARD -i docker0 -j DROP 2>/dev/null; do
                    count=$((count + 1))
                done
                echo "$count"
            ' 2>/dev/null
    ) || true

    if [ "${removed_count:-0}" -gt 0 ]; then
        echo "  Removed ${removed_count} DROP rule(s)"
    else
        echo "  No matching DROP rules found"
    fi
}

# fix_bridge - Restore the Docker bridge network.
#
# Removes test containers, drains DROP rules via nsenter, restarts Docker
# Desktop, then drains DROP rules a second time after restart.
#
# Why drain twice:
#   On Linux, 'systemctl stop/start docker-desktop' may only restart the
#   daemon service while the underlying QEMU VM keeps running. If the VM
#   persists, its iptables state is preserved and the DROP rule survives the
#   restart. The second drain after restart covers this case: if the VM did
#   fully reset the drain is a harmless no-op; if the VM persisted the drain
#   removes the rule that the restart missed.
#
# Why _wait_for_bridge rather than a fixed sleep:
#   docker info readiness races ahead of Docker finishing its iptables setup
#   for docker0. On Linux, that gap can exceed 15 seconds. Polling a live
#   ping is more reliable than any fixed sleep value.
#
# Requires a running Docker daemon (to remove containers and run nsenter).
fix_bridge() {
    echo "Restoring Docker bridge network..."

    echo "Removing test containers..."
    docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
    docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

    echo ""
    echo "Removing iptables DROP rule(s) from FORWARD chain (pre-restart)..."
    _drain_bridge_drop_rules

    echo ""
    echo "Restarting Docker Desktop to rebuild bridge networking..."
    stop_docker_desktop

    # Start Docker Desktop via systemctl only. A nohup fallback was previously
    # used here but was dangerous: if systemctl failed, nohup fired a background
    # Docker Desktop process outside systemd's control that raced against the
    # stopped service. With no fallback, a failed start surfaces a clear error.
    echo "  Starting Docker Desktop..."
    if ! systemctl --user start docker-desktop 2>/dev/null; then
        echo "  Error: 'systemctl --user start docker-desktop' failed."
        echo "  Is Docker Desktop installed and the user systemd session active?"
        echo "  If running Docker Engine (not Desktop), restart manually:"
        echo "    sudo systemctl restart docker"
        return 1
    fi

    echo "  Waiting for Docker daemon (up to 120 seconds)..."
    local i
    for i in $(seq 1 60); do
        if docker info > /dev/null 2>&1; then
            echo "  Docker daemon ready (${i}s)"
            break
        fi
        sleep 2
    done

    if ! docker info > /dev/null 2>&1; then
        echo "  Error: Docker Desktop did not start within 120 seconds"
        return 1
    fi

    # Second drain: if the Linux Docker Desktop VM persisted across the
    # daemon restart, its iptables still contain the DROP rule. Remove it now
    # that the daemon is back up and nsenter can reach the VM again.
    echo ""
    echo "Removing iptables DROP rule(s) from FORWARD chain (post-restart)..."
    _drain_bridge_drop_rules

    echo ""
    echo "Verifying network connectivity (polling up to 60 seconds)..."
    _wait_for_bridge
}

# _wait_for_bridge - Poll container internet connectivity after daemon start.
#
# docker info ready does not mean the docker0 bridge iptables chains are
# initialised. This function retries a ping container every 5 seconds for up
# to 60 seconds, which covers the full bridge-init window on Linux.
_wait_for_bridge() {
    local i ping_ok=0
    for i in $(seq 1 12); do
        if docker run --rm alpine:latest ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
            ping_ok=1
            break
        fi
        echo "  Waiting for bridge to initialise... (${i}/12)"
        sleep 5
    done

    if [ "$ping_ok" -eq 1 ]; then
        echo "  Internet connectivity restored"
    else
        echo "  Connectivity still broken after restart - manual investigation required"
        echo ""
        echo "  To inspect the FORWARD chain inside the Docker VM:"
        echo "    docker run --rm --privileged --pid=host alpine:latest \\"
        echo "      nsenter -t 1 -m -u -n -i iptables -L FORWARD -n"
        return 1
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

# fix_proxy - Remove the bogus proxy from daemon.json and RC files.
#
# On Linux, break_proxy.sh writes an unroutable address to daemon.json.
# Docker Desktop also reads daemon.json for proxy settings on this platform.
# Also strips the break-sentinel block from shell RC files.
#
# MUST be called after stop_docker_desktop.
fix_proxy() {
    local latest_backup rc_file
    echo "Removing broken proxy configuration..."

    echo "Checking daemon.json..."
    if [ -f "$DAEMON_CONFIG" ]; then
        if grep -q "192\.0\.2\.1" "$DAEMON_CONFIG" 2>/dev/null; then
            echo "  Found broken proxy config in daemon.json"
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
                echo "  Found broken proxy block in $rc_file"
                sed -i '/BEGIN DOCKER TRAINING LAB PROXY BREAK/,/END DOCKER TRAINING LAB PROXY BREAK/d' "$rc_file"
                echo "  Removed proxy settings from $rc_file"
            fi
        fi
    done

    echo ""
    echo "Proxy configuration cleaned up"
    echo "Run 'fix-docker-proxy' in this terminal to clear any lingering env vars."
}

# fix_proxyfail - Remove the loopback proxy address from settings.json/daemon.json.
#
# break_proxyfail.sh sets ProxyHTTP/HTTPS to 127.0.0.1:9753 which causes an
# immediate connection-refused error on every pull. Checks both settings.json
# (primary, when Docker Desktop is installed) and daemon.json (fallback).
#
# MUST be called after stop_docker_desktop.
fix_proxyfail() {
    local latest_backup
    echo "Removing broken loopback proxy configuration..."

    # Primary: settings.json (present when Docker Desktop is installed)
    if [ -f "$DESKTOP_SETTINGS" ]; then
        echo "Checking Docker Desktop settings file..."
        latest_backup=$(ls -t "${DESKTOP_SETTINGS}.backup-proxyfail-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$DESKTOP_SETTINGS"
            echo "  Restored settings.json from backup: $(basename "$latest_backup")"
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

    # Fallback: daemon.json (used if settings.json was absent during break)
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

# fix_sso - Restore the Docker CLI credential store configuration.
#
# break_sso.sh on Linux corrupts ~/.docker/config.json by setting credsStore
# to "desktop-broken", a credential helper binary that does not exist in PATH.
# Docker can complete an auth flow (browser SSO or docker login both issue a
# token), but the token save step fails because the helper binary is missing.
# Docker Desktop immediately reverts to a signed-out state, producing a
# sign-in loop.
#
# Restores config.json from the backup written by break_sso.sh. If no backup
# exists, removes the credsStore key so Docker falls back to its built-in
# credential storage.
#
# config.json is only read at login time and is not held open by the daemon,
# so Docker Desktop does not need to be stopped before calling this function.
fix_sso() {
    local config_file="$HOME/.docker/config.json"
    local latest_backup

    echo "Restoring Docker CLI credential store configuration..."

    if [ ! -f "$config_file" ]; then
        echo "  ~/.docker/config.json not found - nothing to fix"
        echo ""
        echo "SSO credential store configuration cleaned up"
        echo "NOTE: Sign back in with: docker login"
        return
    fi

    echo "Checking ~/.docker/config.json..."
    latest_backup=$(ls -t "${config_file}.backup-sso-"* 2>/dev/null | head -1)

    if [ -n "$latest_backup" ]; then
        cp "$latest_backup" "$config_file"
        echo "  Restored config.json from backup: $(basename "$latest_backup")"
    else
        echo "  No backup found, removing broken credsStore key"
        python3 - "$config_file" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)
data.pop('credsStore', None)
with open(path, 'w') as f:
    json.dump(data, f, indent=4)
PYEOF
        echo "  credsStore key removed (Docker will use built-in default)"
    fi

    echo ""
    echo "SSO credential store configuration cleaned up"
    echo "NOTE: Sign back in manually: docker login"
}

# fix_authconfig - Remove the corrupt allowedOrgs value from settings.json.
#
# break_authconfig.sh sets allowedOrgs to a URL-format value instead of a
# plain org slug, causing the sign-in loop. Only uses settings.json — there
# is no daemon.json fallback for this scenario.
#
# MUST be called after stop_docker_desktop.
fix_authconfig() {
    local latest_backup
    echo "Removing broken allowedOrgs configuration..."

    echo "Checking Docker Desktop settings file..."
    if [ -f "$DESKTOP_SETTINGS" ]; then
        latest_backup=$(ls -t "${DESKTOP_SETTINGS}.backup-auth-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$DESKTOP_SETTINGS"
            echo "  Restored settings.json from backup: $(basename "$latest_backup")"
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
