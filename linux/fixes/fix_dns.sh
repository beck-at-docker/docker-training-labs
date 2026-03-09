#!/bin/bash
# fixes/fix_dns.sh - Restore Docker daemon DNS resolution in Docker Desktop
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# The DNS break injects two iptables DROP rules for port 53 into the Docker
# Desktop VM's OUTPUT chain via nsenter. This script removes those rules
# using the same mechanism.

set -e

echo "Fixing Docker Desktop DNS..."

# Verify Docker Desktop is running before attempting anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Remove the DROP rules for port 53 (UDP and TCP) from the VM's OUTPUT chain.
# -D deletes the first matching rule; run once per protocol to match the two
# rules injected by break_dns.sh.
if ! docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c '
        iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true
        iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
    '; then
    echo "Error: Failed to access the Docker VM via nsenter"
    exit 1
fi

# Verify the fix
echo ""
echo "Verifying DNS resolution..."
if docker pull hello-world > /dev/null 2>&1; then
    echo "DNS resolution working"
    docker rmi hello-world > /dev/null 2>&1
else
    echo "DNS still broken - may need Docker Desktop restart"
fi
