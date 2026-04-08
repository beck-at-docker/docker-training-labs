#!/bin/bash
# scenarios/break_authconfig.sh - Simulates an org enforcement misconfiguration
# in Docker Desktop's settings file.
#
# Based on real support cases where Docker Desktop immediately signed users out
# after SSO because allowedOrgs was set to a URL-format value instead of a
# plain organization slug. Docker Desktop's org enforcement check matches
# against plain slugs only - a URL value never matches any real org, so every
# login attempt fires enforcement and triggers an immediate sign-out.
#
# On Linux, Docker Desktop stores its GUI settings in:
#   ~/.docker/desktop/settings-store.json
#
# Unlike proxy settings, allowedOrgs is a Docker Desktop-level key and has
# no equivalent in daemon.json. This lab requires the settings.json file
# to exist; it will error out if Docker Desktop has not been fully initialised.
#
# The break does two things:
#
#   1. settings.json: writes a URL-format array to allowedOrgs
#      (e.g. ["https://hub.docker.com/u/required-org"]) instead of the correct
#      plain-slug format (e.g. ["required-org"]). The enforcement check runs
#      on sign-in and immediately signs the user out because no slug matches.
#
#   2. docker logout: clears stored Docker Hub credentials so the trainee is
#      forced to attempt sign-in and encounter the enforcement failure directly.
#
# Docker Desktop is restarted after the settings change.

set -e

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings-store.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Verify the settings file exists - allowedOrgs is a Docker Desktop GUI key
# with no daemon.json equivalent, so we cannot proceed without it.
if [ ! -f "$DESKTOP_SETTINGS" ]; then
    echo "Error: Docker Desktop settings file not found at:"
    echo "  $DESKTOP_SETTINGS"
    echo "Docker Desktop must be fully initialised before running this lab."
    exit 1
fi

# ------------------------------------------------------------------
# Stop Docker Desktop BEFORE modifying settings.json.
#
# Docker Desktop persists its in-memory configuration back to settings.json
# on clean shutdown. Writing the broken settings first and then quitting
# would cause the graceful shutdown to overwrite our changes. Stopping the
# process first prevents that race.
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
# Corrupt the allowedOrgs value in settings.json.
#
# The correct format for org enforcement is a JSON array of plain org
# slugs: ["my-org-name"]. We write a URL-format value instead. Docker
# Desktop's enforcement check will never match this against any real org
# slug, so every sign-in attempt results in an immediate sign-out loop.
# ------------------------------------------------------------------
cp "$DESKTOP_SETTINGS" "${DESKTOP_SETTINGS}.backup-auth-${BACKUP_TIMESTAMP}"

python3 - "$DESKTOP_SETTINGS" << 'EOF'
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

echo "  Docker Desktop settings updated"

# ------------------------------------------------------------------
# Sign out of Docker Hub to force the sign-in prompt.
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply settings..."

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
echo "Backup saved: ${DESKTOP_SETTINGS}.backup-auth-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptom: Sign-in loop - SSO completes in browser but Docker Desktop immediately signs out"
