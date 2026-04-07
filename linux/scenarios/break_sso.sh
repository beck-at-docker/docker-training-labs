#!/bin/bash
# scenarios/break_sso.sh - Simulates a credential store misconfiguration that
# prevents Docker Desktop from saving login credentials.
#
# Based on real support cases where ~/.docker/config.json had a corrupted or
# incorrect credsStore entry pointing to a credential helper binary that does
# not exist on the system. When Docker completes an authentication flow (SSO
# or plain docker login), it tries to save the resulting token using the
# configured credential helper. If that helper is not found, the save fails
# and Docker Desktop immediately reverts to a signed-out state - producing a
# sign-in loop identical in appearance to a proxy-blocked auth flow, but with
# a completely different root cause.
#
# The break:
#   1. Corrupts ~/.docker/config.json by setting credsStore to a non-existent
#      credential helper name ("desktop-broken"). Docker will look for a binary
#      named docker-credential-desktop-broken in PATH, fail to find it, and be
#      unable to save credentials after any successful auth attempt.
#
#   2. Runs docker logout to clear any existing stored credentials, placing
#      Docker Desktop in a signed-out state immediately.
#
# The trainee must:
#   - Identify the broken credsStore in ~/.docker/config.json
#   - Correct it (remove the key, or set it to a valid helper like "desktop")
#   - Sign back in to Docker Hub
#
# Reference: https://docs.docker.com/engine/reference/commandline/login/#credentials-store

set -e

CONFIG_FILE="$HOME/.docker/config.json"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BROKEN_CREDS_STORE="desktop-broken"

echo "Breaking Docker Desktop..."

if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# ------------------------------------------------------------------
# Ensure ~/.docker/config.json exists.
#
# On a freshly installed Docker Desktop this file may not exist until
# the first docker login. We create a minimal valid config if absent so
# we always have a file to corrupt.
# ------------------------------------------------------------------
mkdir -p "$HOME/.docker"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
{
    "auths": {}
}
EOF
    echo "  Created minimal config.json (was absent)"
fi

# ------------------------------------------------------------------
# Sign out BEFORE corrupting the credential store.
#
# docker logout uses the credential helper to delete stored tokens.
# If we corrupt credsStore first, the helper binary doesn't exist,
# docker logout fails silently (|| true), and the existing session
# stays intact - meaning the break has no visible effect.
# Logging out first while the helper is still valid ensures credentials
# are actually cleared before we break the save path.
# ------------------------------------------------------------------
docker logout > /dev/null 2>&1 || true
echo "  Docker Hub credentials cleared"

cp "$CONFIG_FILE" "${CONFIG_FILE}.backup-sso-${BACKUP_TIMESTAMP}"

# ------------------------------------------------------------------
# Corrupt the credsStore entry.
#
# Docker uses the credsStore key to determine which external credential
# helper binary to call when saving or retrieving credentials. The binary
# name is docker-credential-<value>. Setting this to a non-existent name
# causes every credential save attempt to fail with:
#
#   Error saving credentials: error storing credentials - err: exec:
#   "docker-credential-desktop-broken": executable file not found in $PATH
#
# This means auth can complete (browser SSO or docker login both work up
# to the point of issuing a token) but the token can never be persisted.
# Docker Desktop immediately shows signed-out because nothing was saved.
# ------------------------------------------------------------------
python3 - "$CONFIG_FILE" "$BROKEN_CREDS_STORE" << 'EOF'
import json, sys

path       = sys.argv[1]
bad_helper = sys.argv[2]

with open(path, 'r') as f:
    data = json.load(f)

data['credsStore'] = bad_helper

with open(path, 'w') as f:
    json.dump(data, f, indent=4)
EOF

echo "  ~/.docker/config.json corrupted (credsStore -> $BROKEN_CREDS_STORE)"

echo ""
echo "Docker Desktop broken"
echo "Backup saved: ${CONFIG_FILE}.backup-sso-${BACKUP_TIMESTAMP}"
echo ""
echo "Symptom: Sign-in loop - auth completes but credentials cannot be saved"
