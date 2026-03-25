#!/bin/bash
# install.sh - Install Docker Desktop Training Labs

set -e

INSTALL_DIR="/usr/local/lib/docker-training-labs"
BIN_DIR="/usr/local/bin"

echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker Desktop first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Docker Desktop is not running. Please start Docker Desktop."
    exit 1
fi

echo "Docker Desktop is running"
echo ""

# Create installation directories
echo "Creating installation directories..."
sudo mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/scenarios" "$INSTALL_DIR/tests"

echo "Directories created"
echo ""

# Copy all files
echo "Installing training lab files..."

# Resolve the directory this script lives in regardless of how it was invoked
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy the main script
sudo cp "$SCRIPT_DIR/troubleshootmaclab" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/troubleshootmaclab"

# Copy library files
sudo cp "$SCRIPT_DIR/lib/"*.sh "$INSTALL_DIR/lib/"
sudo chmod +x "$INSTALL_DIR/lib/"*.sh

# Copy scenario files
sudo cp "$SCRIPT_DIR/scenarios/"*.sh "$INSTALL_DIR/scenarios/"
sudo chmod +x "$INSTALL_DIR/scenarios/"*.sh

# Copy test files
sudo cp "$SCRIPT_DIR/tests/"*.sh "$INSTALL_DIR/tests/"
sudo chmod +x "$INSTALL_DIR/tests/"*.sh

echo "Files installed to $INSTALL_DIR"
echo ""

# Create symlink in PATH
echo "Creating command-line tool..."
sudo ln -sf "$INSTALL_DIR/troubleshootmaclab" "$BIN_DIR/troubleshootmaclab"

echo "Command 'troubleshootmaclab' is now available"
echo ""

# Create user state directories with correct ownership.
#
# When this installer is invoked via 'sudo ./install.sh', $HOME and $USER
# resolve to root's home (/var/root) rather than the invoking user's. We
# use $SUDO_USER (set by sudo to the original caller's username) to recover
# the real home directory. The eval echo ~ trick expands ~ for an arbitrary
# username without requiring getent or dscl.
#
# State files (config.json, grades.csv) are intentionally NOT written here.
# Writing them under sudo would create root-owned files that the trainee
# (running as a normal user) cannot update at runtime. Instead, the main
# script bootstraps them on first run when it is executing as the trainee.
# (Contrast with the Linux installer, which writes config.json directly
# because it runs the install as the trainee's user, not as root.)
echo "Initializing training environment..."
USER_HOME=$(eval echo ~"${SUDO_USER:-$USER}")
STATE_DIR="$USER_HOME/.docker-training-labs"
mkdir -p "$STATE_DIR" "$STATE_DIR/reports"
chown -R "${SUDO_USER:-$USER}" "$STATE_DIR"

echo "Training environment initialized"
echo ""

# Append a fix-docker-proxy shell function to the user's .zshrc so that
# bogus proxy environment variables injected by break_proxy.sh can be
# cleared in the live terminal without opening a new one. Fix scripts run
# in a subprocess and cannot unset vars in the parent shell directly.
#
# The sentinel guard prevents the block from being appended more than once
# if bootstrap is re-run.
echo "Configuring shell helper..."
ZSHRC="$USER_HOME/.zshrc"
if [ -f "$ZSHRC" ] && ! grep -q "BEGIN DOCKER TRAINING LABS" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# BEGIN DOCKER TRAINING LABS
# Shell helper installed by docker-training-labs bootstrap.
# Clears proxy environment variables injected by break_proxy.sh in the
# current terminal without requiring a new terminal to be opened.
fix-docker-proxy() {
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy
    echo "Proxy environment variables cleared for this terminal."
}
# END DOCKER TRAINING LABS
EOF
    echo "Shell helper 'fix-docker-proxy' added to $ZSHRC"
elif [ ! -f "$ZSHRC" ]; then
    echo "  Note: $ZSHRC not found, skipping shell helper"
else
    echo "  Shell helper already present in $ZSHRC"
fi
echo ""

echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "To start training, run:"
echo "  troubleshootmaclab"
echo ""
echo "For help, run:"
echo "  troubleshootmaclab --help"
echo ""
echo "Your training data is stored in:"
echo "  $STATE_DIR"
echo ""
