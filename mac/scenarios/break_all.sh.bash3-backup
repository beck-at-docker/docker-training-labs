#!/bin/bash
# break_all.sh - CHAOS MODE - Break all systems

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀"
echo "    CHAOS MODE ACTIVATED"
echo "💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀"
echo ""
echo "Breaking ALL systems..."
echo ""

# Run all break scripts
echo "1/4 Breaking DNS..."
bash "$SCRIPT_DIR/break_dns.sh"
echo ""

echo "2/4 Breaking ports..."
bash "$SCRIPT_DIR/break_ports.sh"
echo ""

echo "3/4 Breaking bridge network..."
bash "$SCRIPT_DIR/break_bridge.sh"
echo ""

echo "4/4 Breaking proxy configuration..."
bash "$SCRIPT_DIR/break_proxy.sh"
echo ""

echo "💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀"
echo " ALL SYSTEMS BROKEN"
echo " Good luck fixing this mess!"
echo "💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀"
