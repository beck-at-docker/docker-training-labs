#!/bin/bash
# setup_fixes.sh - Make all fix scripts executable and test them

set -e

FIXES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Setting Up Development Fix Scripts"
echo "=========================================="
echo ""

# Make all scripts executable
echo "Making scripts executable..."
chmod +x "$FIXES_DIR/fix_dns.sh"
chmod +x "$FIXES_DIR/fix_ports.sh"
chmod +x "$FIXES_DIR/fix_bridge.sh"
chmod +x "$FIXES_DIR/fix_proxy.sh"
chmod +x "$FIXES_DIR/fix_all.sh"

echo "✅ All fix scripts are now executable"
echo ""

# Verify Docker Desktop is running
echo "Checking Docker Desktop..."
if docker info > /dev/null 2>&1; then
    echo "✅ Docker Desktop is running"
else
    echo "❌ Docker Desktop is not running"
    echo "   Please start Docker Desktop before using fix scripts"
    exit 1
fi

echo ""
echo "=========================================="
echo "Setup Complete"
echo "=========================================="
echo ""
echo "Available fix scripts:"
echo "  fix_dns.sh      - Restore DNS resolution"
echo "  fix_ports.sh    - Clean up port squatters"
echo "  fix_bridge.sh   - Restore bridge network"
echo "  fix_proxy.sh    - Remove proxy config"
echo "  fix_all.sh      - Fix everything"
echo ""
echo "Example usage:"
echo "  cd /Users/beck/labs-dd/mac/fixes"
echo "  ./fix_all.sh"
echo ""
echo "For detailed documentation:"
echo "  cat README.md"
echo ""
