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

# Run all break scripts in dependency order: DNS, then ports, then bridge, then proxy.
# Progress output is intentionally cryptic to avoid hinting at the break mechanisms.
bash "$SCRIPT_DIR/break_dns.sh"
echo "working..."

bash "$SCRIPT_DIR/break_ports.sh"
echo "working..."

bash "$SCRIPT_DIR/break_bridge.sh"
echo "working..."

bash "$SCRIPT_DIR/break_proxy.sh"
echo "working..."

echo "=========================================="
echo " DOCKER IS VERY BROKEN"
echo " Good luck fixing this mess!"
echo "=========================================="
