#!/bin/bash
# fix_proxy.sh - Remove broken proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

set -e

echo "Removing broken proxy configuration..."

DOCKER_CONFIG="$HOME/.docker/daemon.json"

# Fix daemon.json
echo "Checking daemon.json..."
if [ -f "$DOCKER_CONFIG" ]; then
    if grep -q "invalid-proxy.local" "$DOCKER_CONFIG" 2>/dev/null; then
        echo "  Found broken proxy config"

        # Check for backup
        LATEST_BACKUP=$(ls -t "${DOCKER_CONFIG}.backup"* 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$DOCKER_CONFIG"
            echo "  Restored from backup: $LATEST_BACKUP"
        else
            # No backup, just remove the file
            rm "$DOCKER_CONFIG"
            echo "  Removed broken daemon.json (no backup found)"
        fi
    else
        echo "  daemon.json is clean"
    fi
else
    echo "  No daemon.json found"
fi

# Fix shell RC files.
# On Linux, .bashrc is checked first (standard interactive shell config),
# then .bash_profile, then .zshrc as a fallback.
echo ""
echo "Checking shell RC files..."

for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$rc_file" ]; then
        if grep -q "BEGIN DOCKER TRAINING LAB PROXY BREAK" "$rc_file" 2>/dev/null; then
            echo "  Found broken proxy in $rc_file"

            # Remove the block between sentinel markers.
            # Linux sed -i does not require the empty-string argument that macOS needs.
            sed -i '/BEGIN DOCKER TRAINING LAB PROXY BREAK/,/END DOCKER TRAINING LAB PROXY BREAK/d' "$rc_file"

            echo "  Removed proxy settings from $rc_file"
        fi
    fi
done

# Clean up environment variables in current shell (won't persist, but helpful for testing)
unset HTTP_PROXY
unset HTTPS_PROXY
unset http_proxy
unset https_proxy
unset NO_PROXY
unset no_proxy

echo ""
echo "Proxy configuration cleaned up"
echo ""
echo "IMPORTANT:"
echo "  1. Restart Docker Desktop for daemon.json changes to take effect"
echo "  2. Restart your terminal for shell changes to take effect"
echo ""
echo "To restart Docker Desktop:"
echo "  - Right-click the Docker icon in your taskbar"
echo "  - Select 'Restart'"
echo ""
echo "To apply shell changes:"
echo "  - Close and reopen your terminal"
echo "  - Or run: source ~/.bashrc"
echo ""

# Test registry access
echo "Testing registry access (may fail until Docker restarts)..."
if docker pull hello-world > /dev/null 2>&1; then
    echo "  Registry access working"
    docker rmi hello-world > /dev/null 2>&1
else
    echo "  Registry access not working yet (restart Docker Desktop)"
fi
