#!/bin/bash
# break_ports.sh - Creates port conflicts for common Docker ports
#
# Occupies five ports that trainees are likely to need:
#   80, 443  - nginx containers named 'port-squatter-*' (easy to find with docker ps)
#   3306     - mysql container (slightly harder - requires knowing the port)
#   5432     - postgres container named 'background-db' (generic name blends in
#              with real infrastructure; less obvious than 'squatter-*' names)
#   8080     - python3 http.server process on the host (not a container at all;
#              trainees must look beyond 'docker ps' to find and kill it)
#
# The mix of container types and the host process is intentional - a real port
# conflict can come from any process, not just Docker containers.

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

# Also try to kill any Python HTTP server on 8080 if PID file is missing
pkill -f "python3 -m http.server 8080" 2>/dev/null || true

# Give processes a moment to clean up
sleep 1

# Start containers that squat on common ports
docker run -d --name port-squatter-80 -p 80:80 nginx:alpine
docker run -d --name port-squatter-443 -p 443:443 nginx:alpine  
docker run -d --name port-squatter-3306 -p 3306:3306 mysql:8 \
    -e MYSQL_ROOT_PASSWORD=dummy

# Start a background process on 8080
nohup python3 -m http.server 8080 </dev/null >/dev/null 2>&1 &
echo $! > /tmp/port_squatter_8080.pid

# Create a less obvious container on port 5432 - the generic name 'background-db'
# blends in with real infrastructure and is harder to spot than 'squatter-*'.
docker run -d --name background-db -p 5432:5432 \
    -e POSTGRES_PASSWORD=dummy postgres:alpine

echo "Docker Desktop broken ..."
echo "Symptoms: New containers will fail to bind with 'address already in use'"
