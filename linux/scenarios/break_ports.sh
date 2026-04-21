#!/bin/bash
# scenarios/break_ports.sh - Creates port conflicts for common Docker ports
#
# Occupies five ports that trainees are likely to need:
#   80, 443  - nginx containers named 'port-squatter-*' (easy to find with docker ps)
#   3306     - mysql container (slightly harder - requires knowing the port)
#   5432     - postgres container named 'background-db' (generic name blends in
#              with real infrastructure; less obvious than 'squatter-*' names)
#   8080     - python3 http.server process on the host (not a container at all;
#              trainees must look beyond 'docker ps' to find and kill it)
#
# python3 is a checked prerequisite on Linux (install.sh requires Python 3.6+),
# so it is safe to use here. The mix of container types and the host process is
# intentional - a real port conflict can come from any process, not just Docker.

# No set -e: each port squatter is attempted independently. A port that is
# already occupied by a system service still satisfies the lab goal (the port
# is unavailable), so we track successes and warn on failures rather than
# aborting the whole script.

echo "Breaking Docker Desktop..."

# ------------------------------------------------------------------
# squat_port <name> <host_port> <image> [extra docker args...]
#
# Attempts to start a container that binds <host_port>. If the port is
# already in use (by a system service or a leftover container) the squatter
# cannot start, but the port is still unavailable - which is the lab goal.
# Prints a clear warning rather than aborting.
# ------------------------------------------------------------------
squat_port() {
    local name=$1
    local host_port=$2
    local image=$3
    shift 3
    # "$@" captures any additional docker flags (e.g. -e MYSQL_ROOT_PASSWORD=...)

    if docker run -d --name "$name" -p "${host_port}:${host_port}" "$@" "$image" \
            > /dev/null 2>&1; then
        echo "  Squatted port $host_port via container '$name'"
    else
        # Remove any partially-created container left behind by a failed run
        docker rm -f "$name" > /dev/null 2>&1 || true
        echo "  Warning: could not start '$name' - port $host_port may already be in use"
        echo "  (port $host_port is still unavailable, which is sufficient for the lab)"
    fi
}

# Clean up any squatters left over from a previous run
docker rm -f port-squatter-80 port-squatter-443 port-squatter-3306 background-db \
    > /dev/null 2>&1 || true

# Kill any existing Python HTTP server on port 8080
if [ -f /tmp/port_squatter_8080.pid ]; then
    if ps -p "$(cat /tmp/port_squatter_8080.pid)" > /dev/null 2>&1; then
        kill "$(cat /tmp/port_squatter_8080.pid)" 2>/dev/null || true
    fi
    rm -f /tmp/port_squatter_8080.pid
fi

# Also kill by process name in case the PID file is stale
pkill -f "python3 -m http.server 8080" 2>/dev/null || true

# Give processes a moment to clean up
sleep 1

# Start containers that squat on common ports. Each call is independent -
# one failure does not prevent the others from running.
squat_port port-squatter-80  80  nginx:alpine
squat_port port-squatter-443 443 nginx:alpine
squat_port port-squatter-3306 3306 mysql:8 -e MYSQL_ROOT_PASSWORD=dummy

# Start a background host process on 8080 - not a container, requires different
# diagnostic and cleanup approach than the containers above.
nohup python3 -m http.server 8080 </dev/null >/dev/null 2>&1 &
PY_PID=$!
echo $PY_PID > /tmp/port_squatter_8080.pid
if ps -p "$PY_PID" > /dev/null 2>&1; then
    echo "  Squatted port 8080 via python3 http.server (pid $PY_PID)"
else
    echo "  Warning: python3 http.server failed to start - port 8080 may already be in use"
fi

# Create a less obvious container on port 5432. The generic name 'background-db'
# blends in with real infrastructure and is harder to spot than 'squatter-*'.
squat_port background-db 5432 postgres:alpine -e POSTGRES_PASSWORD=dummy

# Wait for mysql to finish initialising and actually bind port 3306.
# MySQL can take 10-20 seconds to start; without this wait the port appears
# free and the test script's readiness check passes spuriously.
# Only wait if the container actually started.
if docker ps --filter "name=port-squatter-3306" --format '{{.Names}}' | grep -q port-squatter-3306; then
    echo "Waiting for mysql to bind port 3306..."
    MYSQL_READY=0
    for i in $(seq 1 30); do
        if docker exec port-squatter-3306 mysqladmin ping -u root -pdummy \
                --silent 2>/dev/null; then
            MYSQL_READY=1
            break
        fi
        sleep 2
    done

    if [ "$MYSQL_READY" -eq 0 ]; then
        echo "Warning: mysql did not become ready within 60s - port 3306 may not be held"
    fi
fi

echo "Docker Desktop broken..."
echo "Symptoms: New containers will fail to bind with 'address already in use'"
