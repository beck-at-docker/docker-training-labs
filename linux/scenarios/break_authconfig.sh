#!/bin/bash
# scenarios/break_authconfig.sh - Simulates an org enforcement misconfiguration
# via a registry.json file with a wrong organization slug.
#
# Based on real support cases where an admin pushed a registry.json file via
# MDM with the wrong org slug. Docker Desktop reads registry.json on startup
# and enforces sign-in: the user must be a member of one of the listed orgs.
# If the slug doesn't match any org the user belongs to, DD signs them out
# immediately after every login attempt.
#
# On Linux, Docker Desktop reads sign-in enforcement config from:
#   /usr/share/docker-desktop/registry/registry.json
#
# This file is owned by root and requires sudo to create or modify, which
# reflects how it would be deployed in a real environment (MDM or admin script).
#
# The break does two things:
#
#   1. docker logout: clears stored Docker Hub credentials while Docker Desktop
#      is still running, so the credential helper (docker-credential-desktop)
#      can execute cleanly. Calling logout after DD is stopped silently fails
#      because the helper binary is part of the DD process.
#
#   2. registry.json: creates the enforcement file with a wrong-but-valid org
#      slug ("acme-corp"). The trainee's account is not a member of this org,
#      so every sign-in attempt triggers enforcement and immediately signs
#      them out.
#
# Docker Desktop is restarted after the registry.json is written.

set -e

REGISTRY_DIR="/usr/share/docker-desktop/registry"
REGISTRY_JSON="$REGISTRY_DIR/registry.json"

echo "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# ------------------------------------------------------------------
# Sign out of Docker Hub while DD is still running.
#
# docker-credential-desktop is part of the Docker Desktop process. Calling
# docker logout after DD is stopped silently fails - the helper binary is
# unavailable so credentials are never erased and the trainee stays signed in.
# Running logout here, while DD is confirmed running, ensures the credential
# helper executes and the trainee must sign in to trigger the enforcement loop.
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Write the enforcement file with a wrong org slug.
#
# /usr/share/docker-desktop/registry/ is owned by root. We write the file
# with sudo, which mirrors how this file would arrive in a real environment
# (pushed by MDM or an admin provisioning script). The trainee's account is
# not a member of "acme-corp", so enforcement fires on every sign-in attempt.
# ------------------------------------------------------------------
echo ""
echo "Writing registry.json with wrong org slug..."

sudo mkdir -p "$REGISTRY_DIR"
echo '{"allowedOrgs":["acme-corp"]}' | sudo tee "$REGISTRY_JSON" > /dev/null
sudo chmod 644 "$REGISTRY_JSON"

echo "  Enforcement file written: $REGISTRY_JSON"

# ------------------------------------------------------------------
# Restart Docker Desktop so it picks up the new registry.json.
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker Desktop to apply enforcement config..."

if systemctl --user restart docker-desktop 2>/dev/null; then
    echo "  Restart signal sent via systemctl"
else
    echo "  Warning: Could not restart Docker Desktop via systemctl"
    echo "  Please restart Docker Desktop manually before attempting to sign in"
fi

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
echo "Symptom: Sign in required - login completes but Docker Desktop immediately signs out"
