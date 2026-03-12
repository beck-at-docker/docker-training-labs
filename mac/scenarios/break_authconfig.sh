#!/bin/bash
# break_authconfig.sh - Simulates an org enforcement misconfiguration in
# Docker Desktop's settings store.
#
# Based on real support cases where Docker Desktop immediately signed users out
# after SSO because allowedOrgs was set to a URL-format value instead of a
# plain organization slug. Docker Desktop's org enforcement check matches
# against plain slugs only - a URL value never matches any real org, so every
# login attempt fires enforcement and triggers an immediate sign-out.
#
# The break does two things:
#
#   1. settings-store.json: writes a URL-format array to allowedOrgs
#      (e.g. ["https://hub.docker.com/u/required-org"]) instead of the correct
#      plain-slug format (e.g. ["required-org"]). The enforcement check runs
#      on sign-in and immediately signs the user out because no slug matches
#      the URL string.
#
#   2. docker logout: clears stored Docker Hub credentials so the trainee is
#      forced to attempt sign-in and encounter the enforcement failure directly.
#
# Docker Desktop is restarted after the settings change so it reads the
# updated configuration before the trainee attempts to sign in.

set -e

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Verify the settings store exists - its absence means Docker Desktop hasn't
# been fully initialised and we cannot proceed safely
if [ ! -f "$SETTINGS_STORE" ]; then
    echo "Error: Docker Desktop settings store not found at:"
    echo "  $SETTINGS_STORE"
    exit 1
fi

# ------------------------------------------------------------------
# Corrupt the allowedOrgs value in the settings store.
#
# The correct format for org enforcement is a JSON array of plain org
# slugs: ["my-org-name"]. We write a URL-format value instead. Docker
# Desktop's enforcement check will never match this against any real org
# slug, so every sign-in attempt results in an immediate sign-out loop.
# ------------------------------------------------------------------
cp "$SETTINGS_STORE" "${SETTINGS_STORE}.backup-auth-${BACKUP_TIMESTAMP}"

python3 - "$SETTINGS_STORE" << 'EOF'
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)

# URL-format value - the correct format is just the org slug (e.g.
# "my-company"), not a full URL with scheme and path components.
data['allowedOrgs'] = ["https://hub.docker.com/u/required-org"]

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
EOF

echo "  Settings store updated"

# ------------------------------------------------------------------
# Sign out of Docker Hub to force the sign-in prompt.
#
# Without this, an existing session token may let Docker Desktop run
# for a while before the enforcement check fires on token refresh.
# Logging out ensures the trainee encounters the problem immediately.
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings-store.json.
# Quit via osascript, wait for the process to exit, relaunch, then poll
# docker info until the daemon is accepting connections (max 60 seconds).
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply settings..."

osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true

# Wait for Docker Desktop process to fully exit
for i in $(seq 1 15); do
    if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

open /Applications/Docker.app

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
echo "Backup saved: ${SETTINGS_STORE}.backup-auth-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptom: Sign-in loop - SSO completes in browser but Docker Desktop immediately signs out"
