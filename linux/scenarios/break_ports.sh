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

set -e

echo "Breaking Docker Desktop..."

# Clean up any existing port squatter containers first
docker rm -f port-squatter-80 port-squatter-443 port-squatter-3306 background-db 2>/dev/null || true

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

# Start containers that squat on common ports
docker run -d --name port-squatter-80 -p 80:80 nginx:alpine
docker run -d --name port-squatter-443 -p 443:443 nginx:alpine
docker run -d --name port-squatter-3306 -p 3306:3306 \
    -e MYSQL_ROOT_PASSWORD=dummy mysql:8

# Start a background host process on 8080 - not a container, requires different
# diagnostic and cleanup approach than the containers above.
nohup python3 -m http.server 8080 </dev/null >/dev/null 2>&1 &
echo $! > /tmp/port_squatter_8080.pid

# Create a less obvious container on port 5432. The generic name 'background-db'
# blends in with real infrastructure and is harder to spot than 'squatter-*'.
docker run -d --name background-db -p 5432:5432 \
    -e POSTGRES_PASSWORD=dummy postgres:alpine

# Wait for mysql to finish initialising and actually bind port 3306.
# MySQL can take 10-20 seconds to start; without this wait the port appears
# free and the test script's readiness check passes spuriously.
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

echo "Docker Desktop broken..."
echo "Symptoms: New containers will fail to bind with 'address already in use'"
