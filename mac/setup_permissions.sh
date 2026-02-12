#!/bin/bash
# setup_permissions.sh - Make all scripts executable

cd "$(dirname "$0")"

echo "Setting up file permissions..."

chmod +x troubleshootmaclab
chmod +x bootstrap.sh
chmod +x install.sh
chmod +x scenarios/*.sh
chmod +x tests/*.sh
chmod +x lib/*.sh

echo "✅ All scripts are now executable"
echo ""
echo "Next steps:"
echo "1. Review GIT_SETUP.md for GitHub instructions"
echo "2. Test locally: sudo ./install.sh"
echo "3. Run: troubleshootmaclab"
