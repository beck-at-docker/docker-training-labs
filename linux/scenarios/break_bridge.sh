#!/bin/bash
# scenarios/break_bridge.sh - Corrupts Docker's default bridge network
#
# Mechanism: inserts a DROP rule at the top of the FORWARD chain for all
# traffic originating from docker0. Containers start and receive IPs normally
# because Docker's control plane is unaffected; only data-plane forwarding is
# blocked. The nsenter privileged container is required because iptables rules
# live inside the Docker Desktop VM, not on the Linux host.
#
# The started containers (broken-web, broken-app) give trainees something to
# inspect. Their existence demonstrates that Docker itself is running fine;
# the networking layer is what's broken.

set -e

echo "Breaking Docker Desktop..."

# Clean up any leftover test containers from a previous run
docker rm -f broken-web broken-app 2>/dev/null || true

# Insert a DROP rule at position 1 in the FORWARD chain for all traffic from
# docker0. Containers will start and get IPs normally - only forwarding is
# broken, which is the intended diagnostic challenge.
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    # Delete any stale DROP rule from a previous run, then re-insert at the top
    iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
    iptables -I FORWARD 1 -i docker0 -j DROP
'

# Create containers that appear to work but can't communicate
docker run -d --name broken-web nginx:alpine
docker run -d --name broken-app alpine:latest sleep 3600

echo "Docker Desktop broken"
echo "Symptoms: Containers can't reach each other or internet"
