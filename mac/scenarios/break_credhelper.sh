#!/bin/bash
# break_credhelper.sh - Corrupts the credsStore in ~/.docker/config.json so
# the Docker CLI cannot find its credential helper binary.
#
# Docker Desktop for Mac configures ~/.docker/config.json with
# "credsStore": "desktop", which tells the CLI to shell out to
# docker-credential-desktop for every registry auth lookup - including
# anonymous pulls, since the CLI always checks for stored credentials for
# the target registry host before making the request. If that binary can't
# be found, EVERY registry operation fails immediately, before any network
# request is even made:
#
#   error getting credentials - err: exec: "docker-credential-desktop-broken":
#   executable file not found in $PATH, out: ``
#
# This is a genuinely common Docker Desktop support case (usually caused by
# a stale/corrupt config.json, a botched manual edit, or a PATH problem
# after a reinstall) - the daemon is completely healthy, but the CLI can't
# even get as far as making an HTTP request.

set -e

CONFIG_FILE="$HOME/.docker/config.json"

echo "Breaking Docker Desktop..."

if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

mkdir -p "$HOME/.docker"
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{}' > "$CONFIG_FILE"
fi

# Preserve the original file so fix_credhelper can restore it exactly,
# rather than guessing at whatever else was already in config.json
# (auths, currentContext, plugin config, etc).
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup-credhelper-$(date +%s)"

python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, 'r') as f:
    data = json.load(f)
# "desktop" is the correct value on Mac - Docker Desktop installs the real
# docker-credential-desktop binary into /usr/local/bin. Point credsStore at
# a helper name that does not exist instead.
data['credsStore'] = 'desktop-broken'
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

echo ""
echo "Docker Desktop broken"
echo "Symptoms: docker pull / docker login / docker push all fail immediately with"
echo "  'error getting credentials - err: exec: \"docker-credential-desktop-broken\": executable file not found in \$PATH'"
