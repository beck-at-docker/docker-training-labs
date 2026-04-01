#!/bin/bash
# break_sso.sh - Simulates an SSO authentication loop caused by proxy misconfiguration.
#
# Based on real support cases (AT&T / multiple enterprise customers) where Docker
# Desktop's SSO login flow produced an immediate sign-out loop. In each case the
# root cause was a manually configured proxy that blocked Docker's auth/identity
# endpoints while leaving registry traffic accessible via ProxyExclude.
#
# The break creates two conditions:
#
#   1. settings-store.json: sets proxy mode to "manual" with a non-routable
#      address (192.0.2.1, RFC 5737 TEST-NET). The ProxyExclude list covers
#      Docker registry and token-service hostnames, leaving hub.docker.com,
#      login.docker.com, and id.docker.com exposed to the bogus proxy.
#
#      Result: anonymous image pulls succeed (registry + auth.docker.io bypass
#      the proxy), but SSO completion fails because Docker Desktop's backend
#      callback to hub.docker.com is blocked.
#
#   2. docker logout: removes the stored Docker Hub credentials, placing Docker
#      Desktop in a signed-out state. When the trainee attempts SSO, the browser
#      auth succeeds but Docker Desktop's token exchange with hub.docker.com goes
#      through the bogus proxy and fails, producing an immediate sign-out loop.
#
# Docker Desktop is restarted after the settings change so it reads the new
# proxy configuration before the trainee attempts to sign in.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Verify the settings store exists - it is created during Docker Desktop's
# first run, so its absence means Docker Desktop hasn't fully initialised
if [ ! -f "$SETTINGS_STORE" ]; then
    echo "Error: Docker Desktop settings store not found at:"
    echo "  $SETTINGS_STORE"
    exit 1
fi

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE modifying settings-store.json.
#
# Docker Desktop persists its in-memory configuration back to
# settings-store.json on clean shutdown. Writing the broken settings
# first and then quitting would cause the graceful shutdown to
# overwrite our changes. Stopping the process first prevents that race.
# ------------------------------------------------------------------
echo ""
echo "Stopping Docker Desktop before modifying settings..."

osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true

# Wait for the Docker Desktop process to exit
for i in $(seq 1 15); do
    if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ------------------------------------------------------------------
# Method 1: Corrupt the Docker Desktop settings store with an asymmetric
#           proxy configuration.
#
# The ProxyExclude list intentionally covers registry and token-service
# hostnames so that image pulls continue to work. It deliberately omits
# hub.docker.com, login.docker.com, and id.docker.com - the endpoints
# Docker Desktop calls to complete the SSO token exchange.
#
# Keys written:
#   ProxyHTTPMode        - switched to "manual"
#   ProxyHTTP / HTTPS    - bogus non-routable proxy address
#   ProxyExclude         - registry hosts only, auth endpoints absent
#   ContainersProxy*     - left at system so containers are unaffected
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-sso-${BACKUP_TIMESTAMP}"

python3 - "$SETTINGS_STORE" << 'EOF'
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

bogus_proxy = "http://192.0.2.1:8080"

# Exclude Docker registry and token-service endpoints so pulls still work.
# hub.docker.com, login.docker.com, and id.docker.com are intentionally
# absent - those are the SSO completion endpoints that the break targets.
registry_exclude = (
    "registry-1.docker.io,"
    "production.cloudflare.docker.com,"
    "index.docker.io,"
    "auth.docker.io"
)

data['ProxyHTTPMode']            = 'manual'
data['ProxyHTTP']                = bogus_proxy
data['ProxyHTTPS']               = bogus_proxy
data['ProxyExclude']             = registry_exclude
data['ContainersProxyHTTPMode']  = 'system'
data['ContainersProxyHTTP']      = ''
data['ContainersProxyHTTPS']     = ''
data['ContainersProxyExclude']   = ''

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF

echo "  Settings store updated"

# ------------------------------------------------------------------
# Method 2: Sign out of Docker Hub to force the sign-in prompt.
#
# docker-credential-desktop accesses the macOS Keychain directly and
# does not require the Docker Desktop process to be running. Running
# docker logout here (after process exit) is safe.
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Relaunch Docker Desktop so it starts fresh with the broken settings.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply proxy settings..."

open /Applications/Docker.app

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
echo "Backup saved: ${SETTINGS_STORE}.backup-sso-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptom: SSO sign-in loop; image pulls still work"
