#!/bin/bash
# break_dns.sh - Breaks container DNS resolution by injecting iptables rules
# inside the Docker Desktop VM that drop all outbound DNS traffic (port 53).
#
# The Docker VM is ephemeral, so these rules do not survive a Docker Desktop
# restart. The intended fix path is to remove the rules directly via nsenter.
# Restarting Docker Desktop also clears them but is treated as a fallback.

set -e

echo "Breaking Docker Desktop DNS resolution..."

# Verify Docker Desktop is running
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Inject iptables DROP rules for port 53 (UDP and TCP) into the Docker VM's
# network namespace via nsenter. This drops all DNS queries leaving the VM,
# which breaks name resolution for every container.
docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c '
        iptables -I OUTPUT -p udp --dport 53 -j DROP
        iptables -I OUTPUT -p tcp --dport 53 -j DROP
    '

echo "DNS break applied"
echo "Symptom: Containers cannot resolve external hostnames"
