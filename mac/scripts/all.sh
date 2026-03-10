#!/bin/bash
# all.sh - Restore all Docker Desktop systems
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
echo "  3. Bridge Network"
echo "  4. Proxy Configuration"
echo ""
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=========================================="

# Fix in reverse order of dependency
echo ""
echo "[1/4] Fixing Bridge Network (affects everything)..."
bash "$SCRIPT_DIR/bridge.sh"

echo ""
echo "=========================================="
echo ""
echo "[2/4] Fixing DNS Resolution..."
bash "$SCRIPT_DIR/dns.sh"

echo ""
echo "=========================================="
echo ""
echo "[3/4] Fixing Proxy Configuration..."
bash "$SCRIPT_DIR/proxy.sh"

echo ""
echo "=========================================="
echo ""
echo "[4/4] Fixing Port Conflicts..."
bash "$SCRIPT_DIR/ports.sh"

echo ""
echo "=========================================="
echo "All Systems Restored"
echo "=========================================="
echo ""
echo "Docker Desktop was restarted automatically during the proxy fix."
echo "Verify everything is working:"
echo "  docker pull hello-world"
echo "  docker run --rm alpine:latest ping -c 2 google.com"
echo "  docker run -p 8080:80 nginx:alpine"
echo ""
