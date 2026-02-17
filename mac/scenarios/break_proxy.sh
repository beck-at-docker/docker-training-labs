#!/bin/bash
# break_proxy.sh - Corrupts proxy settings

set -e

echo "Breaking proxy configuration..."

# Generate timestamp once for consistent backup naming
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Method 1: Set invalid proxy in Docker daemon config
DOCKER_CONFIG="$HOME/.docker/daemon.json"
mkdir -p "$HOME/.docker"

# Backup existing config with timestamp (consistent with shell RC backup)
if [ -f "$DOCKER_CONFIG" ]; then
    cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    DAEMON_BACKUP_CREATED="yes"
else
    DAEMON_BACKUP_CREATED="no"
fi

# Write broken proxy config
cat > "$DOCKER_CONFIG" << 'EOF'
{
  "proxies": {
    "http-proxy": "http://invalid-proxy.local:3128",
    "https-proxy": "http://invalid-proxy.local:3128"
  }
}
EOF

# Method 2: Set conflicting environment variables in shell RC files
# Detect which shell RC file to modify
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    # Default to .zshrc on macOS
    SHELL_RC="$HOME/.zshrc"
fi

# Backup the RC file
if [ -f "$SHELL_RC" ]; then
    cp "$SHELL_RC" "${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    SHELL_BACKUP_CREATED="yes"
else
    SHELL_BACKUP_CREATED="no"
fi

# Add broken proxy settings (with marker for easy removal)
cat >> "$SHELL_RC" << 'EOF'

# BEGIN DOCKER TRAINING LAB PROXY BREAK - DO NOT EDIT
# These settings were added by the Docker training lab break script
export HTTP_PROXY=http://192.0.2.1:8080
export HTTPS_PROXY=http://192.0.2.1:8080
export NO_PROXY=
# END DOCKER TRAINING LAB PROXY BREAK
EOF

echo ""
echo "⚠️  IMPORTANT: You must restart Docker Desktop for daemon.json changes to take effect!"
echo "⚠️  You must also restart your terminal or run: source $SHELL_RC"
echo ""
echo "To restart Docker Desktop:"
echo "  1. Click the Docker whale icon in your menu bar"
echo "  2. Select 'Restart'"
echo "  3. Wait for Docker Desktop to fully restart"
echo ""
echo "✅ Proxy configuration broken in:"
echo "   - $DOCKER_CONFIG (requires Docker restart)"
echo "   - $SHELL_RC (requires terminal restart)"
echo ""

if [ "$DAEMON_BACKUP_CREATED" = "yes" ] || [ "$SHELL_BACKUP_CREATED" = "yes" ]; then
    echo "Backups saved:"
    [ "$DAEMON_BACKUP_CREATED" = "yes" ] && echo "   - ${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    [ "$SHELL_BACKUP_CREATED" = "yes" ] && echo "   - ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    echo ""
fi

echo "Symptoms: Image pulls fail, container internet access fails"
