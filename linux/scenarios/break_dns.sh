#!/bin/bash
# scenarios/break_dns.sh - Breaks Docker daemon DNS resolution by injecting
# iptables DROP rules for port 53 into the Docker Desktop VM's OUTPUT chain
# via nsenter.
#
# The daemon process runs inside the VM and uses the VM's network stack for
# its own DNS lookups (e.g. registry resolution during docker pull). Dropping
# port 53 traffic on OUTPUT prevents the daemon from resolving any external
# hostnames, producing errors like:
#
#   lookup http.docker.internal on 192.168.65.x:53:
#   write udp ...: write: operation not permitted
#
# The VM is ephemeral - iptables rules do not survive a Docker Desktop restart.
# Fix path: remove the DROP rules via nsenter (full marks), or restart Docker
# Desktop as a last resort.

set -e

echo "Breaking Docker Desktop DNS resolution..."

# Confirm Docker Desktop is running before attempting anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Inject DROP rules for port 53 (UDP and TCP) into the VM's OUTPUT chain.
if ! docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c '
        iptables -I OUTPUT -p udp --dport 53 -j DROP
        iptables -I OUTPUT -p tcp --dport 53 -j DROP
    '; then
    echo "Error: Failed to apply iptables rules inside the VM"
    exit 1
fi

echo ""
echo "Docker Desktop DNS resolution broken"
echo "Symptom: docker pull and registry access fail with DNS errors"
