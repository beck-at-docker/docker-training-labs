#!/bin/bash
# fix_all.sh - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Restoring ALL Docker Desktop Systems"
echo "=========================================="
echo ""
echo "This will fix:"
echo "  1. DNS Resolution"
echo "  2. Port Conflicts"
echo "  3. Proxy Configuration"
echo ""
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=========================================="

echo ""
echo "[1/3] Fixing DNS Resolution..."
bash "$SCRIPT_DIR/fix_dns.sh"

echo ""
echo "=========================================="
echo ""
echo "[2/3] Fixing Port Conflicts..."
bash "$SCRIPT_DIR/fix_ports.sh"

echo ""
echo "=========================================="
echo ""
echo "[3/3] Fixing Proxy Configuration..."
bash "$SCRIPT_DIR/fix_proxy.sh"

echo ""
echo "=========================================="
echo "All Systems Restored"
echo "=========================================="
echo ""
echo "IMPORTANT: Restart Docker Desktop for proxy changes to take effect."
echo ""
echo "To restart Docker Desktop:"
echo "  1. Right-click the Docker icon in your taskbar"
echo "  2. Select 'Restart'"
echo "  3. Wait for Docker Desktop to fully restart"
echo ""
echo "After Docker restarts, verify everything works:"
echo "  docker run --rm alpine:latest ping -c 2 google.com"
echo "  docker pull hello-world"
echo ""
