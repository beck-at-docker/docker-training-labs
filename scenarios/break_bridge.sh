#!/bin/bash
# break_bridge.sh - Corrupts Docker's default bridge network

set -e

echo "Corrupting Docker bridge network..."

# Create overlapping custom networks
docker network create --subnet=172.17.0.0/16 fake-bridge-1 2>/dev/null || true
docker network create --subnet=172.17.0.0/16 fake-bridge-2 2>/dev/null || true

# Corrupt the default bridge by messing with iptables in the VM
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    # Save existing rules
    iptables-save > /tmp/iptables.backup
    
    # Delete Docker chain rules
    iptables -D FORWARD -o docker0 -j DOCKER 2>/dev/null || true
    iptables -D FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i docker0 ! -o docker0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null || true
    
    # Add conflicting rules
    iptables -I FORWARD 1 -i docker0 -j DROP
'

# Create containers that appear to work but can't communicate
docker run -d --name broken-web nginx:alpine
docker run -d --name broken-app alpine:latest sleep 3600

echo "✅ Bridge network corrupted"
echo "Symptoms: Containers can't reach each other or internet"
