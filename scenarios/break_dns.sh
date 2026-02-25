#!/bin/bash
# break_dns.sh - Breaks Docker daemon DNS resolution by injecting invalid
# nameservers into ~/.docker/daemon.json, then restarts Docker Desktop so the
# daemon picks up the configuration.
#
# The symptom is deliberately confusing: nslookup inside containers still works
# (Docker's embedded resolver at 127.0.0.11 ignores daemon.json), but docker
# pull and any other operation the daemon process itself performs against
# external hostnames will fail. This mirrors real-world misconfigurations where
# proxy or DNS settings are set at the wrong layer.
#
# Fix path: edit or remove ~/.docker/daemon.json, then restart Docker Desktop.

set -e

DAEMON_JSON="$HOME/.docker/daemon.json"
DAEMON_JSON_BACKUP="${DAEMON_JSON}.break_dns_backup"

echo "Breaking Docker Desktop DNS configuration..."

# Verify Docker Desktop is running
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Back up any existing daemon.json so the test script can verify the break
# is in place, and the trainee can reference original settings if needed.
if [ -f "$DAEMON_JSON" ]; then
    cp "$DAEMON_JSON" "$DAEMON_JSON_BACKUP"
else
    # Sentinel value so the test knows there was no prior config to restore to
    echo "__empty__" > "$DAEMON_JSON_BACKUP"
fi

# Write invalid DNS servers. 192.0.2.0/24 is TEST-NET-1 (RFC 5737) - reserved,
# never routable, guaranteed not to respond.
cat > "$DAEMON_JSON" << 'EOF'
{
  "dns": ["192.0.2.1", "192.0.2.2"]
}
EOF

echo "Injected invalid DNS servers into $DAEMON_JSON"

# Restart Docker Desktop so the daemon process loads the new config.
echo "Restarting Docker Desktop (this will take about 30-60 seconds)..."
osascript -e 'tell application "Docker Desktop" to quit' 2>/dev/null || true

echo "Waiting for Docker Desktop to stop..."
stop_wait=0
while pgrep -q "Docker Desktop" 2>/dev/null; do
    sleep 1
    stop_wait=$((stop_wait + 1))
    if [ $stop_wait -ge 30 ]; then
        echo "Warning: Docker Desktop did not stop cleanly within 30 seconds, continuing anyway"
        break
    fi
done

sleep 2

echo "Starting Docker Desktop..."
open -a "Docker Desktop"

echo "Waiting for Docker Desktop to start..."
start_wait=0
max_wait=120
while ! docker info &>/dev/null 2>&1; do
    sleep 2
    start_wait=$((start_wait + 2))
    if [ $start_wait -ge $max_wait ]; then
        echo "Error: Docker Desktop did not start within ${max_wait} seconds"
        exit 1
    fi
done

echo ""
echo "Docker Desktop DNS configuration broken"
echo "Symptom: docker pull and registry access fail with DNS errors"
echo "Note:    nslookup inside containers may still appear to work"
