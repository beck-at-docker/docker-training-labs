#!/bin/bash
# scenarios/break_sso.sh - Simulates an SSO authentication loop caused by proxy misconfiguration.
#
# Based on real support cases where Docker Desktop's SSO login flow produced
# an immediate sign-out loop. The root cause was a manually configured proxy
# that blocked Docker's auth/identity endpoints while leaving registry traffic
# accessible via the no-proxy / ProxyExclude list.
#
# On Linux, Docker Desktop stores its GUI-level proxy config in:
#   ~/.docker/desktop/settings.json
#
# This mirrors the Mac/Windows settings-store.json approach. If that file
# does not exist (older Docker Desktop versions or different installation),
# the script falls back to ~/.docker/daemon.json with a no-proxy list.
#
# The break creates two conditions:
#
#   1. settings.json (or daemon.json fallback): sets proxy mode to "manual"
#      with a non-routable address (192.0.2.1, RFC 5737 TEST-NET). The
#      ProxyExclude / no-proxy list covers registry and token-service hosts,
#      leaving hub.docker.com, login.docker.com, and id.docker.com exposed.
#
#      Result: anonymous pulls succeed; SSO completion fails.
#
#   2. docker logout: removes stored Docker Hub credentials, placing Docker
#      Desktop in a signed-out state. When the trainee attempts SSO, the
#      browser auth succeeds but the token exchange with hub.docker.com goes
#      through the bogus proxy and fails.

set -e

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Breaking Docker Desktop..."

if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Registry and token-service hosts excluded from the proxy so pulls still work.
# hub.docker.com, login.docker.com, and id.docker.com are intentionally absent.
REGISTRY_EXCLUDE="registry-1.docker.io,production.cloudflare.docker.com,index.docker.io,auth.docker.io"

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE modifying settings files.
#
# Docker Desktop persists its in-memory configuration back to
# settings.json on clean shutdown. Writing the broken settings first
# and then restarting would cause the graceful shutdown to overwrite
# our changes. Stopping the process first prevents that race.
# ------------------------------------------------------------------
echo ""
echo "Stopping Docker Desktop before modifying settings..."

if systemctl --user stop docker-desktop 2>/dev/null; then
    echo "  Stopped via systemctl"
else
    pkill -f "docker-desktop" 2>/dev/null || true
    echo "  Stopped via pkill"
fi

# Wait for the Docker Desktop process to exit
for i in $(seq 1 15); do
    if ! pgrep -f "docker-desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ------------------------------------------------------------------
# Method 1: Corrupt Docker Desktop's GUI proxy settings.
#
# Prefer ~/.docker/desktop/settings.json (Docker Desktop's own config),
# which allows the same asymmetric ProxyExclude approach used on Mac and
# Windows. Fall back to daemon.json if the file does not exist.
# ------------------------------------------------------------------
if [ -f "$DESKTOP_SETTINGS" ]; then
    cp "$DESKTOP_SETTINGS" "${DESKTOP_SETTINGS}.backup-${BACKUP_TIMESTAMP}"

    python3 - "$DESKTOP_SETTINGS" << EOF
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

bogus_proxy = "http://192.0.2.1:8080"
registry_exclude = "$REGISTRY_EXCLUDE"

# NOTE: Docker Desktop uses a two-field pattern for manual proxy config.
# ProxyHTTP/HTTPS is the address shown in the UI (display/remembered value);
# Docker Desktop only routes traffic through OverrideProxyHTTP/HTTPS.
# Without setting the Override fields, DD falls back to system proxy on
# restart and the break has no effect.
data['ProxyHTTPMode']                = 'manual'
data['ProxyHTTP']                    = bogus_proxy  # UI display / remembered value
data['ProxyHTTPS']                   = bogus_proxy  # UI display / remembered value
data['OverrideProxyHTTP']            = bogus_proxy  # active value DD routes traffic through
data['OverrideProxyHTTPS']           = bogus_proxy  # active value DD routes traffic through
data['ProxyExclude']                 = registry_exclude
data['ContainersProxyHTTPMode']      = 'system'
data['ContainersProxyHTTP']          = ''
data['ContainersProxyHTTPS']         = ''
data['ContainersOverrideProxyHTTP']  = ''
data['ContainersOverrideProxyHTTPS'] = ''
data['ContainersProxyExclude']       = ''

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF
    echo "  Docker Desktop settings updated (${DESKTOP_SETTINGS})"

else
    # Fallback: use daemon.json with a no-proxy list. This controls the Docker
    # daemon's proxy, not Docker Desktop's GUI layer, so the SSO symptom may
    # present differently (docker info fails rather than a GUI loop). The
    # diagnostic path - finding proxy config and correcting exclusions - is the
    # same.
    mkdir -p "$HOME/.docker"

    if [ -f "$DAEMON_CONFIG" ]; then
        cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    fi

    cat > "$DAEMON_CONFIG" << EOF
{
  "proxies": {
    "http-proxy": "http://192.0.2.1:8080",
    "https-proxy": "http://192.0.2.1:8080",
    "no-proxy": "$REGISTRY_EXCLUDE"
  }
}
EOF
    echo "  daemon.json updated with asymmetric proxy (fallback path)"
    echo "  Note: ~/.docker/desktop/settings.json not found; using daemon.json"
fi

# ------------------------------------------------------------------
# Method 2: Sign out to force the sign-in prompt
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings.
# On Linux, Docker Desktop is managed as a systemd user service.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply proxy settings..."

if systemctl --user start docker-desktop 2>/dev/null; then
    echo "  Restart signal sent via systemctl"
else
    echo "  Warning: Could not restart Docker Desktop automatically via systemctl"
    echo "  Please restart Docker Desktop manually before attempting to sign in"
fi

echo "Docker Desktop must be started manually..."
echo "  Waiting for Docker Desktop to restart..."
DOCKER_READY=0
for i in $(seq 1 30); do
    if docker info &>/dev/null 2>&1; then
        DOCKER_READY=1
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" -eq 0 ]; then
    echo "  Warning: Docker Desktop did not come back within 60s"
    echo "  Wait a moment before attempting to sign in"
fi

echo ""
echo "Docker Desktop broken"
echo ""
echo "Symptom: SSO sign-in loop; image pulls still work"
