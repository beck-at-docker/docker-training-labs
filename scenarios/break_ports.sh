#!/bin/bash
# break_ports.sh - Creates port conflicts for common Docker ports

set -e

echo "Breaking port availability..."

# Start containers that squat on common ports
docker run -d --name port-squatter-80 -p 80:80 nginx:alpine
docker run -d --name port-squatter-443 -p 443:443 nginx:alpine  
docker run -d --name port-squatter-3306 -p 3306:3306 mysql:8 \
    -e MYSQL_ROOT_PASSWORD=dummy

# Also start a background process on 8080
nohup python3 -m http.server 8080 </dev/null >/dev/null 2>&1 &
echo $! > /tmp/port_squatter_8080.pid

# Create a hidden container that will persist
docker run -d --name .hidden-postgres -p 5432:5432 \
    -e POSTGRES_PASSWORD=dummy postgres:alpine

echo "✅ Ports blocked: 80, 443, 3306, 5432, 8080"
echo "Symptoms: New containers will fail to bind ports with 'address already in use'"
