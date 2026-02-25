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
# Config and grades files are bootstrapped on first run by the main script,
# so we only need to ensure the directories exist and are owned by the
# invoking user (not root).
echo "Initializing training environment..."
USER_HOME=$(eval echo ~"${SUDO_USER:-$USER}")
STATE_DIR="$USER_HOME/.docker-training-labs"
mkdir -p "$STATE_DIR" "$STATE_DIR/reports"
chown -R "${SUDO_USER:-$USER}" "$STATE_DIR"

echo "Training environment initialized"
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
