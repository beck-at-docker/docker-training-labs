#!/bin/bash
# scenarios/break_proxy.sh - Corrupts proxy settings
#
# Sets invalid proxy configuration in two separate places to simulate the
# kind of layered misconfiguration that happens in corporate environments:
#
#   1. ~/.docker/daemon.json: the Docker daemon reads this on startup.
#      Setting an invalid proxy here means image pulls fail even after a
#      terminal restart because the daemon is the one making the requests.
#      Requires a Docker Desktop restart to take effect.
#
#   2. Shell RC file (~/.bashrc or ~/.bash_profile): sets HTTP_PROXY and
#      HTTPS_PROXY environment variables that will conflict with any valid
#      proxy config once the terminal is reloaded. The variables are wrapped
#      in sentinel comments (BEGIN/END markers) for clean programmatic removal.
#
# A timestamp-based backup is created for both files so nothing is permanently
# lost and trainees can restore from backup as one valid fix path.

set -e

echo "Breaking Docker Desktop..."

# Generate timestamp once for consistent backup naming
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ------------------------------------------------------------------
# Method 1: Set invalid proxy in Docker daemon config
# ------------------------------------------------------------------
DOCKER_CONFIG="$HOME/.docker/daemon.json"
mkdir -p "$HOME/.docker"

# Backup existing config with timestamp
if [ -f "$DOCKER_CONFIG" ]; then
    cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    DAEMON_BACKUP_CREATED=1
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

# ------------------------------------------------------------------
# Method 2: Set conflicting environment variables in shell RC file
# On Linux, ~/.bashrc is the standard interactive shell config.
# ------------------------------------------------------------------
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    # Default to .bashrc on Linux
    SHELL_RC="$HOME/.bashrc"
fi

# Backup the RC file
if [ -f "$SHELL_RC" ]; then
    cp "$SHELL_RC" "${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    SHELL_BACKUP_CREATED=1
fi

# Add broken proxy settings wrapped in sentinel markers for clean removal
cat >> "$SHELL_RC" << 'EOF'

# BEGIN DOCKER TRAINING LAB PROXY BREAK - DO NOT EDIT
# These settings were added by the Docker training lab break script
export HTTP_PROXY=http://192.0.2.1:8080
export HTTPS_PROXY=http://192.0.2.1:8080
export NO_PROXY=
# END DOCKER TRAINING LAB PROXY BREAK
EOF

echo ""
echo "IMPORTANT: You must restart Docker Desktop for changes to take effect!"
echo "You must also restart your terminal or run: source $SHELL_RC"
echo ""
echo "Proxy configuration broken in:"
echo "   - $DOCKER_CONFIG (requires Docker restart)"
echo "   - $SHELL_RC (requires terminal restart)"
echo ""

if [ -n "$DAEMON_BACKUP_CREATED" ] || [ -n "$SHELL_BACKUP_CREATED" ]; then
    echo "Backups saved:"
    [ -n "$DAEMON_BACKUP_CREATED" ] && echo "   - ${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    [ -n "$SHELL_BACKUP_CREATED" ] && echo "   - ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    echo ""
fi

echo "Docker Desktop broken..."
echo "Symptoms: Image pulls fail, container internet access fails"
