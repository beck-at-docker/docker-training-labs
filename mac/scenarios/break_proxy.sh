#!/bin/bash
# break_proxy.sh - Corrupts proxy settings

set -e

echo "Breaking proxy configuration..."

# Method 1: Set invalid proxy in Docker daemon config
DOCKER_CONFIG="$HOME/.docker/daemon.json"
mkdir -p "$HOME/.docker"

# Backup existing config
[ -f "$DOCKER_CONFIG" ] && cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup"

# Write broken proxy config
cat > "$DOCKER_CONFIG" << 'EOF'
{
  "proxies": {
    "http-proxy": "http://invalid-proxy.local:3128",
    "https-proxy": "http://invalid-proxy.local:3128"
  }
}
EOF

# Method 2: Set conflicting environment variables
cat >> ~/.zshrc << 'EOF'

# Broken proxy settings (added by break script)
export HTTP_PROXY=http://192.0.2.1:8080
export HTTPS_PROXY=http://192.0.2.1:8080
export NO_PROXY=
EOF

source ~/.zshrc

echo "⚠️  Restart Docker Desktop for daemon.json changes to take effect"
echo "✅ Proxy configuration broken"
echo "Symptoms: Image pulls fail, container internet access fails"
