#!/bin/bash
# bootstrap.sh - One-command installer for Docker Desktop Training Labs (Linux)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs-linux/main/lab/bootstrap.sh | bash
#
# Override branch:
#   BRANCH=dev curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs-linux/main/lab/bootstrap.sh | bash

set -e

GITHUB_REPO="beck-at-docker/docker-training-labs-linux"
BRANCH="${BRANCH:-main}"
TEMP_DIR=$(mktemp -d)

echo ""
echo "=========================================="
echo "Docker Desktop Training Labs Installer"
echo "=========================================="
echo ""

# ------------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------------
echo "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
    echo ""
    echo "Error: Docker Desktop is not installed."
    echo "       Install from: https://docs.docker.com/desktop/install/linux-install/"
    echo ""
    exit 1
fi

if ! docker info &>/dev/null; then
    echo ""
    echo "Error: Docker Desktop is not running. Please start it first."
    echo ""
    exit 1
fi

echo "  Docker Desktop is running"

if ! command -v python3 &>/dev/null; then
    echo ""
    echo "Error: python3 is required but not installed."
    echo "       On Debian/Ubuntu: sudo apt install python3"
    echo "       On Fedora/RHEL:   sudo dnf install python3"
    echo ""
    exit 1
fi

echo "  python3 found"
echo ""

# ------------------------------------------------------------------
# Download repo
# ------------------------------------------------------------------
echo "Downloading training labs from GitHub..."
echo "  Repo   : $GITHUB_REPO"
echo "  Branch : $BRANCH"
echo ""

cd "$TEMP_DIR"

if command -v git &>/dev/null; then
    git clone --depth 1 --branch "$BRANCH" \
        "https://github.com/${GITHUB_REPO}.git" docker-training-labs
else
    # Fallback: download ZIP and extract without git
    echo "git not found - downloading tarball instead..."
    curl -fsSL "https://github.com/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" \
        | tar -xz
    mv "docker-training-labs-linux-${BRANCH}" docker-training-labs
fi

cd docker-training-labs/lab

echo "  Download complete"
echo ""

# ------------------------------------------------------------------
# Run the installer (requires sudo for /usr/local writes)
# ------------------------------------------------------------------
echo "Running installer (sudo required for system directories)..."
echo ""

if [ "$EUID" -eq 0 ]; then
    bash install.sh
else
    sudo bash install.sh
fi

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "Bootstrap complete."
echo "Start training with:"
echo "  troubleshootlinuxlab"
echo "=========================================="
echo ""
