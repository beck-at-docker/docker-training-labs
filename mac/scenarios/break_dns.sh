#!/bin/bash
# break_dns.sh - Corrupts DNS resolution in Docker Desktop VM

set -e

echo "🔧 Breaking Docker Desktop networking..."

# Verify Docker Desktop is running
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

# Method 1: Corrupt DNS settings in the Docker VM
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    # Backup original resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true
    
    # Replace with invalid DNS servers
    echo "nameserver 192.0.2.1" > /etc/resolv.conf
    echo "nameserver 192.0.2.2" >> /etc/resolv.conf
    
    # Make it immutable to persist the break
    chattr +i /etc/resolv.conf 2>/dev/null || true
'

echo "✅ Docker networking broken - DNS resolution will fail"
echo "Symptoms: Containers cannot resolve external hostnames"
