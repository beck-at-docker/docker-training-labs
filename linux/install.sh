#!/bin/bash
# install.sh - Install Docker Desktop Training Labs (Linux)
#
# Run directly or via bootstrap.sh. Requires sudo (writes to /usr/local).

set -e

INSTALL_DIR="/usr/local/lib/docker-training-labs"
BIN_DIR="/usr/local/bin"
STATE_DIR="$HOME/.docker-training-labs"

echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# ------------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------------
echo "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
    echo "Error: docker is not installed."
    echo "       Install Docker Desktop from:"
    echo "       https://docs.docker.com/desktop/install/linux-install/"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running. Please start it first."
    exit 1
fi

echo "  Docker Desktop is running"

# python3 is used by lib/state.sh for JSON state management
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required but not installed."
    echo "       On Debian/Ubuntu: sudo apt install python3"
    echo "       On Fedora/RHEL:   sudo dnf install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 6 ]; }; then
    echo "Error: Python 3.6+ required. Found Python $PYTHON_VERSION"
    exit 1
fi

echo "  Python $PYTHON_VERSION found"
echo ""

# ------------------------------------------------------------------
# Create directories
# ------------------------------------------------------------------
echo "Creating installation directories..."

sudo mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/scenarios" "$INSTALL_DIR/tests"
mkdir -p "$STATE_DIR/reports"

echo "  Directories created"
echo ""

# ------------------------------------------------------------------
# Copy files
# ------------------------------------------------------------------
echo "Installing training lab files..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo cp "$SCRIPT_DIR/troubleshootlinuxlab"   "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/troubleshootlinuxlab"

sudo cp "$SCRIPT_DIR/lib/"*.sh               "$INSTALL_DIR/lib/"
sudo chmod +x "$INSTALL_DIR/lib/"*.sh

sudo cp "$SCRIPT_DIR/scenarios/"*.sh         "$INSTALL_DIR/scenarios/"
sudo chmod +x "$INSTALL_DIR/scenarios/"*.sh

sudo cp "$SCRIPT_DIR/tests/"*.sh             "$INSTALL_DIR/tests/"
sudo chmod +x "$INSTALL_DIR/tests/"*.sh

echo "  Files installed to $INSTALL_DIR"
echo ""

# ------------------------------------------------------------------
# Create symlink so 'troubleshootlinuxlab' works from any shell
# ------------------------------------------------------------------
echo "Creating command-line tool..."
sudo ln -sf "$INSTALL_DIR/troubleshootlinuxlab" "$BIN_DIR/troubleshootlinuxlab"
echo "  Command 'troubleshootlinuxlab' is now available"
echo ""

# ------------------------------------------------------------------
# Initialise state files
# ------------------------------------------------------------------
echo "Initialising training environment..."

# Write the initial config file. This runs as the trainee's user (not root),
# so the file is owned correctly and can be updated at runtime.
# Contrast with Mac install.sh, which runs as root via sudo and therefore
# defers config creation to the main script's first-run bootstrap.
cat > "$STATE_DIR/config.json" << EOF
{
  "version": "1.0.0",
  "trainee_id": "$USER",
  "current_scenario": null,
  "scenario_start_time": null
}
EOF

if [ ! -f "$STATE_DIR/grades.csv" ]; then
    echo "trainee_id,scenario,score,timestamp,duration_seconds" > "$STATE_DIR/grades.csv"
fi

echo "  Training environment initialised"
echo ""

# Append a fix-docker-proxy shell function to the user's .bashrc so that
# bogus proxy environment variables injected by break_proxy.sh can be
# cleared in the live terminal without opening a new one. Fix scripts run
# in a subprocess and cannot unset vars in the parent shell directly.
#
# The sentinel guard prevents the block from being appended more than once
# if bootstrap is re-run.
echo "Configuring shell helper..."
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ] && ! grep -q "BEGIN DOCKER TRAINING LABS" "$BASHRC"; then
    cat >> "$BASHRC" << 'EOF'

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
    echo "  Shell helper 'fix-docker-proxy' added to $BASHRC"
elif [ ! -f "$BASHRC" ]; then
    echo "  Note: $BASHRC not found, skipping shell helper"
else
    echo "  Shell helper already present in $BASHRC"
fi
echo ""

echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "To start training, run:"
echo "  troubleshootlinuxlab"
echo ""
echo "For help:"
echo "  troubleshootlinuxlab --help"
echo ""
echo "Your training data is stored in:"
echo "  $STATE_DIR"
echo ""
