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
# Scenarios that write to settings-store.json or daemon.json (PROXY, PROXYFAIL)
# MUST be applied after Docker Desktop is stopped. Docker flushes
# its in-memory configuration back to the settings file on a clean shutdown,
# which would overwrite any changes written while the daemon was running.
# Call stop_docker_desktop before invoking any of those three functions.
#
# SSO is the exception: its fix operates on ~/.docker/config.json, which is
# only read at login time and does not require the daemon to be stopped.
#
# Scenarios that operate via live iptables or container removal (DNS, BRIDGE,
# PORT) require Docker to be running and do not need a restart to take effect.

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings-store.json"
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
# Tries both 'iptables' and 'iptables-legacy' because on modern Linux the
# default iptables symlink may point to iptables-nft while the Docker daemon
# (or a previous version of this break script) inserted the rule via
# iptables-legacy (or vice versa). Draining both backends is a no-op for
# whichever one doesn't hold the rule.
#
# Called both before and after the Docker Desktop restart: before to clean up
# the injected rule while Docker is running, after to catch the case where the
# Linux Docker Desktop VM persists across a daemon-only restart and keeps its
# iptables state intact.
_drain_bridge_drop_rules() {
    local removed_count
    removed_count=$(
        docker run --rm --privileged --pid=host alpine:latest \
            nsenter -t 1 -m -u -n -i sh -c '
                count=0
                for ipt in iptables iptables-legacy; do
                    command -v "$ipt" > /dev/null 2>&1 || continue
                    while $ipt -D FORWARD -i docker0 -j DROP 2>/dev/null; do
                        count=$((count + 1))
                    done
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
# Removes test containers, then drains the injected DROP rules from the
# FORWARD chain via nsenter. No Docker Desktop restart is performed.
#
# Why no restart:
#   On this platform, 'systemctl stop/start docker-desktop' stops only the
#   Desktop GUI/management frontend while the underlying VM and dockerd keep
#   running (daemon ready in ~2s is the tell). The frontend stop/start cycle
#   touches Docker's iptables state and can leave the NAT MASQUERADE rule
#   missing, which breaks container internet access even after the DROP rule
#   is gone. Leaving dockerd alone preserves the NAT and DOCKER-FORWARD
#   chain state that was working before the break.
#
# Why drain twice (both backends):
#   On modern Linux the default iptables symlink may point to iptables-nft
#   while the injected rule lives in iptables-legacy (or vice versa). Draining
#   both is a no-op for whichever backend doesn't hold the rule.
#
# Requires a running Docker daemon (to remove containers and run nsenter).
fix_bridge() {
    echo "Restoring Docker bridge network..."

    echo "Removing test containers..."
    docker rm -f broken-web 2>/dev/null && echo "  Removed broken-web" || true
    docker rm -f broken-app 2>/dev/null && echo "  Removed broken-app" || true

    echo ""
    echo "Removing iptables DROP rule(s) from FORWARD chain..."
    _drain_bridge_drop_rules

    echo ""
    echo "Verifying network connectivity (polling up to 60 seconds)..."
    if _wait_for_bridge; then
        return 0
    fi

    # DROP rule is gone and Docker's own chains are intact, but ping still
    # fails. This is an unexpected state - surface the diagnostic output
    # (already printed by _wait_for_bridge) and return failure so the caller
    # knows manual intervention is needed.
    return 1
}

# _wait_for_bridge - Poll container internet connectivity after daemon start.
#
# docker info readiness races ahead of Docker finishing its iptables setup
# for docker0. Retries a ping container every 5 seconds for up to 3 minutes.
# On failure, dumps the FORWARD chain and ip_forward state so the cause is
# visible in the log rather than requiring a separate diagnostic run.
_wait_for_bridge() {
    local i ping_ok=0
    for i in $(seq 1 12); do
        if docker run --rm alpine:latest ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
            ping_ok=1
            break
        fi
        echo "  Waiting for bridge... (${i}/12, $(( i * 5 ))s elapsed)"
        sleep 5
    done

    if [ "$ping_ok" -eq 1 ]; then
        echo "  Internet connectivity restored"
        return 0
    fi

    echo "  Connectivity still broken after 60 seconds."
    echo ""
    echo "  --- Diagnostic: iptables state ---"
    docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c '
            echo "=== FORWARD chain ==="
            iptables -L FORWARD -n -v 2>&1 || echo "(iptables not available)"
            echo ""
            echo "=== DOCKER-FORWARD chain ==="
            iptables -L DOCKER-FORWARD -n -v 2>&1 || echo "(DOCKER-FORWARD not found)"
            echo ""
            echo "=== DOCKER-ISOLATION chains ==="
            iptables -L DOCKER-ISOLATION-STAGE-1 -n -v 2>&1 || echo "(DOCKER-ISOLATION-STAGE-1 not found)"
            iptables -L DOCKER-ISOLATION-STAGE-2 -n -v 2>&1 || echo "(DOCKER-ISOLATION-STAGE-2 not found)"
            echo ""
            echo "=== nat POSTROUTING ==="
            iptables -t nat -L POSTROUTING -n -v 2>&1 || echo "(nat POSTROUTING check failed)"
            echo ""
            echo "=== nat DOCKER ==="
            iptables -t nat -L DOCKER -n -v 2>&1 || echo "(nat DOCKER not found)"
            echo ""
            echo "=== iptables-legacy FORWARD ==="
            iptables-legacy -L FORWARD -n -v 2>&1 || echo "(iptables-legacy not available)"
            echo ""
            echo "=== ip_forward ==="
            cat /proc/sys/net/ipv4/ip_forward 2>&1
            echo ""
            echo "=== docker0 link ==="
            ip link show docker0 2>&1 || echo "(docker0 not found)"
            echo ""
            echo "=== routes ==="
            ip route show 2>&1
        ' 2>/dev/null || echo "  (nsenter failed - cannot read VM state)"
    echo "  --- End diagnostic ---"
    echo ""
    echo "  To inspect manually:"
    echo "    docker run --rm --privileged --pid=host alpine:latest \\"
    echo "      nsenter -t 1 -m -u -n -i iptables -L FORWARD -n -v"
    return 1
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

# fix_proxyfail - Restore proxy settings via the backend API.
#
# break_proxyfail.sh sets a loopback proxy (127.0.0.1:9753) via the backend
# socket API. This function restores proxy mode to system via the same API
# while Docker Desktop is running.
#
# Falls back to restoring settings-store.json from backup if the socket is
# unavailable. In that case Docker Desktop must be restarted manually.
#
# Does NOT require stop_docker_desktop.
fix_proxyfail() {
    local latest_backup
    local backend_sock="$HOME/.docker/desktop/backend.sock"
    echo "Removing broken loopback proxy configuration..."

    if [ -S "$backend_sock" ]; then
        echo "Restoring proxy settings via Docker Desktop backend API..."
        HTTP_STATUS=$(curl \
            --silent \
            --unix-socket "$backend_sock" \
            -X POST \
            -H "Content-Type: application/json" \
            -w "%{http_code}" \
            -o /tmp/proxyfail-fix-response.txt \
            "http://localhost/app/settings" \
            -d '{
                "vm": {
                    "proxy": {
                        "mode":    {"value": "system"},
                        "http":    {"value": ""},
                        "https":   {"value": ""},
                        "exclude": {"value": ""}
                    },
                    "containersProxy": {
                        "mode":    {"value": "system"},
                        "http":    {"value": ""},
                        "https":   {"value": ""},
                        "exclude": {"value": ""}
                    }
                }
            }' 2>&1) || true
        rm -f /tmp/proxyfail-fix-response.txt

        if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
            echo "  Proxy reset to system mode via API (HTTP $HTTP_STATUS)"
        else
            echo "  Warning: API returned HTTP $HTTP_STATUS - falling back to file restore"
            _fix_proxyfail_file_fallback
        fi
    else
        echo "  Backend socket not available - falling back to file restore"
        echo "  Docker Desktop will need to be restarted for the fix to take effect"
        _fix_proxyfail_file_fallback
    fi

    echo ""
    echo "Proxy failure configuration cleaned up"
}

# _fix_proxyfail_file_fallback - Restore settings-store.json from backup.
# Used when the backend socket is unavailable (Docker Desktop fully stopped).
_fix_proxyfail_file_fallback() {
    local latest_backup
    if [ -f "$SETTINGS_STORE" ]; then
        latest_backup=$(ls -t "${SETTINGS_STORE}.backup-proxyfail-"* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_STORE"
            echo "  Restored settings-store.json from backup: $(basename "$latest_backup")"
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
        echo "  Settings store not found - nothing to restore"
    fi
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

# fix_authconfig - Remove the registry.json enforcement file.
#
# break_authconfig.sh creates /usr/share/docker-desktop/registry/registry.json
# with a wrong org slug, causing a sign-in enforcement loop. Removing the file
# disables enforcement entirely and allows sign-in to succeed.
#
# Does not require Docker Desktop to be stopped - registry.json is read at
# startup, so the fix takes effect after the next restart.
fix_authconfig() {
    local registry_json="/usr/share/docker-desktop/registry/registry.json"
    echo "Removing broken org enforcement configuration..."

    if [ -f "$registry_json" ]; then
        sudo rm -f "$registry_json"
        echo "  Removed: $registry_json"
    else
        echo "  registry.json not found - nothing to fix"
    fi

    echo ""
    echo "Org enforcement configuration removed"
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
