#!/bin/bash
# break_dns.sh - Corrupts Docker Desktop DNS configuration by injecting invalid
# nameservers into ~/.docker/daemon.json, then restarts Docker Desktop so the
# configuration takes effect.
#
# The backup file (daemon.json.break_dns_backup) is used by test_dns.sh to
# verify the break is in the expected state and can be used by the trainee to
# restore original settings if needed.

set -e

DAEMON_JSON="$HOME/.docker/daemon.json"
DAEMON_JSON_BACKUP="$HOME/.docker/daemon.json.break_dns_backup"

echo "Breaking Docker Desktop DNS configuration..."

# Verify Docker Desktop is running before we start
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Back up the existing daemon.json so it can be compared against later.
# If no file exists, write a sentinel value so we know to restore to nothing.
if [ -f "$DAEMON_JSON" ]; then
    cp "$DAEMON_JSON" "$DAEMON_JSON_BACKUP"
else
    echo "__empty__" > "$DAEMON_JSON_BACKUP"
fi

# Overwrite daemon.json with invalid DNS servers (192.0.2.0/24 is TEST-NET-1,
# a reserved block guaranteed never to route to a real nameserver).
cat > "$DAEMON_JSON" << 'EOF'
{
  "dns": ["192.0.2.1", "192.0.2.2"]
}
EOF

echo "Injected invalid DNS servers into daemon.json"

# Restart Docker Desktop so the daemon picks up the new configuration.
echo "Restarting Docker Desktop (this will take about 30-60 seconds)..."
osascript -e 'tell application "Docker Desktop" to quit' 2>/dev/null || true

# Wait for Docker Desktop to fully exit before reopening it.
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

# Reopen Docker Desktop.
echo "Starting Docker Desktop..."
open -a "Docker Desktop"

# Poll until the daemon is responsive again.
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
echo "Symptom: Containers cannot resolve external hostnames"
