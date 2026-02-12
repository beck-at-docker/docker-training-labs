#!/bin/bash
# install.sh - Install Docker Desktop Training Labs

set -e

INSTALL_DIR="/usr/local/lib/docker-training-labs"
BIN_DIR="/usr/local/bin"
STATE_DIR="$HOME/.docker-training-labs"

echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker Desktop first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker Desktop is not running. Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker Desktop is running"
echo ""

# Create installation directories
echo "Creating installation directories..."
sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR/lib"
sudo mkdir -p "$INSTALL_DIR/scenarios"
sudo mkdir -p "$INSTALL_DIR/tests"
mkdir -p "$STATE_DIR"
mkdir -p "$STATE_DIR/reports"

echo "✅ Directories created"
echo ""

# Copy all files
echo "Installing training lab files..."

# Get the script directory
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

echo "✅ Files installed to $INSTALL_DIR"
echo ""

# Create symlink in PATH
echo "Creating command-line tool..."
sudo ln -sf "$INSTALL_DIR/troubleshootmaclab" "$BIN_DIR/troubleshootmaclab"

echo "✅ Command 'troubleshootmaclab' is now available"
echo ""

# Initialize state
echo "Initializing training environment..."
cat > "$STATE_DIR/config.json" << EOF
{
  "version": "1.0.0",
  "install_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "trainee_id": "$USER",
  "current_scenario": null,
  "scenario_start_time": null
}
EOF

# Initialize grading database
cat > "$STATE_DIR/grades.csv" << EOF
trainee_id,scenario,score,timestamp,duration_seconds
EOF

echo "✅ Training environment initialized"
echo ""

echo "=========================================="
echo "Installation Complete! 🎉"
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
