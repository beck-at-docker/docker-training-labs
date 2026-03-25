#!/bin/bash
# break_all.sh - CHAOS MODE - Break all systems

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "    CHAOS MODE ACTIVATED"
echo "=========================================="
echo ""
echo "Breaking Docker Desktop..."
echo ""

# Run all break scripts in order: ports first (so container images are pulled
# while outbound connectivity is still intact), then proxy (triggers a Docker
# restart), then DNS and bridge (iptables rules injected after the restart
# persist until the trainee fixes them). Progress output is intentionally
# cryptic to avoid hinting at the break mechanisms.
bash "$SCRIPT_DIR/break_ports.sh"
echo "working..."

bash "$SCRIPT_DIR/break_proxy.sh"
echo "working..."

bash "$SCRIPT_DIR/break_dns.sh"
echo "working..."

bash "$SCRIPT_DIR/break_bridge.sh"
echo "working..."

echo "=========================================="
echo " DOCKER IS VERY BROKEN"
echo " Good luck fixing this mess!"
echo "=========================================="
