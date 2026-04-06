#!/bin/bash
# install.sh - Install Docker Desktop Training Labs (Linux)
#
# Run directly or via bootstrap.sh. Requires sudo (writes to /usr/local).

set -e

INSTALL_DIR="/usr/local/lib/docker-training-labs"
BIN_DIR="/usr/local/bin"

# When called via "sudo bash install.sh" from bootstrap.sh, $HOME and $USER
# resolve to root. Resolve back to the invoking user so that state files,
# grades, and shell helpers land in the right home directory.
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

STATE_DIR="$REAL_HOME/.docker-training-labs"

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

# When install.sh is invoked via "sudo bash install.sh" from bootstrap.sh,
# this process runs as root. Docker Desktop on Linux is per-user, so the
# root account cannot reach the user's socket. Re-run the check as the
# invoking user if available; otherwise fall back to a direct check.
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    DOCKER_CHECK="sudo -u $SUDO_USER docker info"
else
    DOCKER_CHECK="docker info"
fi

if ! $DOCKER_CHECK &>/dev/null; then
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
# Note: $STATE_DIR is created in the "Initialise state files" block below,
# as the real user, so it is owned correctly.

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

# Create state directory as the real user so it is owned correctly.
# sudo -u preserves ownership when SUDO_USER is set; falls through to
# plain mkdir when running directly (no sudo context).
if [ -n "$SUDO_USER" ]; then
    sudo -u "$REAL_USER" mkdir -p "$STATE_DIR/reports"
else
    mkdir -p "$STATE_DIR/reports"
fi

cat > "$STATE_DIR/config.json" << EOF
{
  "version": "1.0.0",
  "trainee_id": "$REAL_USER",
  "current_scenario": null,
  "scenario_start_time": null
}
EOF

# Set ownership back to the real user if we're running as root.
[ -n "$SUDO_USER" ] && chown -R "$REAL_USER" "$STATE_DIR"

if [ ! -f "$STATE_DIR/grades.csv" ]; then
    echo "trainee_id,scenario,score,timestamp,duration_seconds" > "$STATE_DIR/grades.csv"
    [ -n "$SUDO_USER" ] && chown "$REAL_USER" "$STATE_DIR/grades.csv"
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
BASHRC="$REAL_HOME/.bashrc"
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
