#!/bin/bash
# break_ports.sh - Creates port conflicts for common Docker ports

set -e

echo "Breaking port availability..."

# Clean up any existing port squatter containers first
docker rm -f port-squatter-80 port-squatter-443 port-squatter-3306 .hidden-postgres 2>/dev/null || true

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

# Create a hidden container that will persist
docker run -d --name .hidden-postgres -p 5432:5432 \
    -e POSTGRES_PASSWORD=dummy postgres:alpine

echo "✅ Ports blocked: 80, 443, 3306, 5432, 8080"
echo "Symptoms: New containers will fail to bind ports with 'address already in use'"
