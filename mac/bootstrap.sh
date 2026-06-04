#!/bin/bash
# bootstrap.sh - One-command installer for Docker Training Labs from GitHub
#
# Usage:
#   export GH_TOKEN=$(gh auth token)
#   curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
#     "https://raw.githubusercontent.com/docker/docker-training-labs/main/mac/bootstrap.sh" \
#     | bash
#
# Override branch:
#   BRANCH=dev <above command>

set -e

GITHUB_REPO="docker/docker-training-labs"
BRANCH="${BRANCH:-main}"
TEMP_DIR=$(mktemp -d)

echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# Require a GitHub token — the repo is private.
if [ -z "$GH_TOKEN" ]; then
    echo "Error: GH_TOKEN is not set."
    echo ""
    echo "Run:"
    echo "  export GH_TOKEN=\$(gh auth token)"
    echo "  curl -fsSL -H \"Authorization: Bearer \$GH_TOKEN\" \\"
    echo "    \"https://raw.githubusercontent.com/${GITHUB_REPO}/main/mac/bootstrap.sh\" \\"
    echo "    | bash"
    exit 1
fi

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker Desktop first."
    echo "   Download from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Error: Docker Desktop is not running. Please start Docker Desktop."
    exit 1
fi

echo "Docker Desktop is running"
echo ""

# Clone from GitHub
echo "Downloading training labs from GitHub..."
cd "$TEMP_DIR"

if command -v git &> /dev/null; then
    git clone --depth 1 --branch "$BRANCH" \
        "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPO}.git" docker-training-labs
else
    # Fallback to downloading tarball if git not available
    echo "Git not found, downloading tarball..."
    curl -fsSL -L \
        -H "Authorization: Bearer $GH_TOKEN" \
        "https://github.com/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" \
        | tar -xz
    mv "docker-training-labs-${BRANCH}" docker-training-labs
fi

cd docker-training-labs

echo "Download complete"
echo ""

# Capture absolute path before handing off to sudo, which may reset CWD.
# Using 'sudo bash <path>' matches the Linux bootstrap pattern and avoids
# the 'command not found' error caused by sudo resolving relative paths.
# install.sh lives under mac/ in the monorepo, not at the repo root.
INSTALL_SCRIPT="$(pwd)/mac/install.sh"

# Run installer
echo "Installing (requires sudo)..."
if [ "$EUID" -eq 0 ]; then
    bash "$INSTALL_SCRIPT"
else
    sudo bash "$INSTALL_SCRIPT"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Start training with:"
echo "  troubleshootmaclab"
echo ""
echo "For help:"
echo "  troubleshootmaclab --help"
echo ""
