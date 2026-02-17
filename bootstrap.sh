#!/bin/bash
# bootstrap.sh - One-command installer for Docker Training Labs from GitHub

set -e

GITHUB_REPO="beck-at-docker/docker-training-labs"
BRANCH="${BRANCH:-main}"
TEMP_DIR=$(mktemp -d)

echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker Desktop first."
    echo "   Download from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker Desktop is not running. Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker Desktop is running"

# Check for Python 3 (required for state management)
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. This is required for state management."
    echo ""
    echo "On macOS, Python 3 should be pre-installed. If not, install it with:"
    echo "  brew install python3"
    echo ""
    echo "Or download from: https://www.python.org/downloads/"
    exit 1
fi

echo "✅ Python 3 found"
echo ""

# Clone from GitHub
echo "Downloading training labs from GitHub..."
cd "$TEMP_DIR"

if command -v git &> /dev/null; then
    git clone --depth 1 --branch "$BRANCH" "https://github.com/${GITHUB_REPO}.git" docker-training-labs
else
    # Fallback to downloading tarball if git not available
    echo "Git not found, downloading tarball..."
    curl -fsSL "https://github.com/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz
    mv "docker-training-labs-${BRANCH}" docker-training-labs
fi

cd docker-training-labs

echo "✅ Download complete"
echo ""

# Run installer
echo "Installing (requires sudo)..."
if [ "$EUID" -eq 0 ]; then
    ./install.sh
else
    sudo ./install.sh
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "Installation Complete! 🎉"
echo "=========================================="
echo ""
echo "Start training with:"
echo "  troubleshootmaclab"
echo ""
echo "For help:"
echo "  troubleshootmaclab --help"
echo ""
