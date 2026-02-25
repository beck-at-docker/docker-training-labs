#!/bin/bash
# scenarios/break_dns.sh - Corrupts DNS resolution inside the Docker Desktop VM
#
# Mechanism: iptables rules are inserted into the VM's network namespace
# (via privileged nsenter) that DROP all UDP and TCP traffic on port 53.
# This blocks DNS at the network level regardless of resolv.conf contents,
# which makes the symptom clearly observable but non-obvious to diagnose.
#
# Fix path trainees are expected to discover:
#   1. Inspect containers and note DNS failures
#   2. Enter the VM namespace or inspect via privileged container
#   3. Identify the DROP rules in the OUTPUT and FORWARD chains
#   4. Remove or flush the offending iptables rules
#   5. Verify DNS resolves again

set -e

echo "Breaking Docker Desktop networking..."

# Confirm Docker Desktop is running before attempting anything
if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

echo "Inserting iptables rules to block DNS inside the Docker Desktop VM..."

# Build the iptables command as a single semicolon-delimited string so it
# passes cleanly through nsenter without heredoc quoting issues.
IPTABLES_CMD="iptables-save > /tmp/iptables.dns-backup 2>/dev/null || true; \
iptables -I OUTPUT  -p udp --dport 53 -j DROP; \
iptables -I OUTPUT  -p tcp --dport 53 -j DROP; \
iptables -I FORWARD -p udp --dport 53 -j DROP; \
iptables -I FORWARD -p tcp --dport 53 -j DROP; \
echo 'iptables rules applied'"

docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c "$IPTABLES_CMD"

if [ $? -ne 0 ]; then
    echo "Error: Failed to apply iptables rules inside the VM"
    exit 1
fi

# Sanity-check that the rules actually landed
VERIFY=$(docker run --rm --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -n -i sh -c 'iptables -L OUTPUT -n' 2>&1)

if ! echo "$VERIFY" | grep -q "DROP"; then
    echo "Error: iptables rules did not apply - OUTPUT chain has no DROP rules"
    exit 1
fi

echo ""
echo "Docker networking broken - DNS resolution will fail inside containers"
echo ""
echo "Symptoms: Containers cannot resolve external hostnames"
echo ""
echo "Test it:"
echo "  docker run --rm alpine:latest nslookup google.com"
echo "  (should time out or fail)"
echo ""
