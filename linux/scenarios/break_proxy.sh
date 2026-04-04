#!/bin/bash
# scenarios/break_proxy.sh - Corrupts proxy settings
#
# Sets invalid proxy configuration in two separate places to simulate the
# kind of layered misconfiguration that happens in corporate environments.
#
# Linux supports two distinct Docker runtime flavors, each with a DIFFERENT
# daemon config path. Writing to the wrong file has NO effect:
#
#   Docker Desktop for Linux:
#     Config:   ~/.docker/daemon.json       (user-writable, no sudo needed)
#     Restart:  systemctl --user restart docker-desktop
#
#   Docker Engine (plain dockerd):
#     Config:   /etc/docker/daemon.json     (system file, requires sudo)
#     Restart:  sudo systemctl restart docker
#
# This script auto-detects which flavor is running and writes to the correct
# path. A common lab failure mode is writing to ~/.docker/daemon.json on a
# Docker Engine system - the Engine ignores that file entirely, so the break
# has no effect and docker pull succeeds as if nothing happened.
#
# The shell RC break (HTTP_PROXY / HTTPS_PROXY) is applied regardless of
# flavor. Note that shell env vars affect only the Docker CLI process - they
# do NOT propagate to the daemon, which runs as a systemd service with its
# own isolated environment. Both layers must be fixed for a full solution.
#
# A timestamp-based backup is created for all modified files so nothing is
# permanently lost and trainees can restore from backup as one valid fix path.

set -e

echo "Breaking Docker Desktop..."

# Generate timestamp once for consistent backup naming
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ------------------------------------------------------------------
# Detect which Docker flavor is running: Desktop or plain Engine.
#
# docker info reports "Docker Desktop" in the OperatingSystem field when
# Docker Desktop for Linux is the active runtime. Falling back to checking
# the systemd user unit catches cases where Docker Desktop is running but
# the info call races with startup.
# ------------------------------------------------------------------
DOCKER_FLAVOR="engine"
if docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "docker desktop"; then
    DOCKER_FLAVOR="desktop"
elif systemctl --user is-active docker-desktop &>/dev/null; then
    DOCKER_FLAVOR="desktop"
fi

echo "Detected Docker flavor: $DOCKER_FLAVOR"
echo ""

# ------------------------------------------------------------------
# Method 1: Set invalid proxy in Docker daemon config
#
# CRITICAL: The config file path differs by flavor.
#
#   Docker Desktop: ~/.docker/daemon.json      (user-writable, no sudo)
#   Docker Engine:  /etc/docker/daemon.json    (system file, requires sudo)
#
# Writing the wrong file silently does nothing - Docker Desktop ignores
# /etc/docker/daemon.json and Docker Engine ignores ~/.docker/daemon.json.
# Auto-detect above ensures we always write to the right location.
# ------------------------------------------------------------------
if [ "$DOCKER_FLAVOR" = "desktop" ]; then
    DOCKER_CONFIG="$HOME/.docker/daemon.json"
    mkdir -p "$HOME/.docker"
    DAEMON_BACKUP_CREATED=0
    if [ -f "$DOCKER_CONFIG" ]; then
        cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
        DAEMON_BACKUP_CREATED=1
    fi
    # Write broken proxy config using the RFC 5737 TEST-NET address (192.0.2.1).
    # This address is routable but guaranteed unroutable on any real network,
    # producing a connection timeout rather than an immediate refusal.
    cat > "$DOCKER_CONFIG" << 'EOF'
{
  "proxies": {
    "http-proxy": "http://192.0.2.1:8080",
    "https-proxy": "http://192.0.2.1:8080"
  }
}
EOF
else
    # Docker Engine: config lives at the system level and requires sudo.
    DOCKER_CONFIG="/etc/docker/daemon.json"
    DAEMON_BACKUP_CREATED=0
    if [ -f "$DOCKER_CONFIG" ]; then
        sudo cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
        DAEMON_BACKUP_CREATED=1
    fi
    sudo tee "$DOCKER_CONFIG" > /dev/null << 'EOF'
{
  "proxies": {
    "http-proxy": "http://192.0.2.1:8080",
    "https-proxy": "http://192.0.2.1:8080"
  }
}
EOF
fi

# ------------------------------------------------------------------
# Method 2: Set conflicting environment variables in shell RC file.
#
# Shell env vars are inherited by child processes of the shell, which
# includes the Docker CLI. However, they do NOT affect the Docker daemon
# (dockerd), which is launched by systemd with its own clean environment.
# A trainee who only fixes the shell RC and never touches daemon.json will
# still fail the docker pull test - both layers must be resolved.
#
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

# ------------------------------------------------------------------
# Restart Docker so it reads the updated daemon config.
#
# daemon.json is not written back by Docker on shutdown, so there is
# no race condition - we can restart without stopping first.
# The restart command differs by flavor:
#   Docker Desktop: systemctl --user restart docker-desktop
#   Docker Engine:  sudo systemctl restart docker
# ------------------------------------------------------------------
echo ""
echo "Restarting Docker to apply proxy settings..."

if [ "$DOCKER_FLAVOR" = "desktop" ]; then
    if systemctl --user restart docker-desktop 2>/dev/null; then
        echo "  Restart signal sent via systemctl --user (Docker Desktop)"
    else
        pkill -f "docker-desktop" 2>/dev/null || true
        echo "  Warning: Could not restart Docker Desktop automatically"
        echo "  Please restart Docker Desktop manually before starting the lab"
    fi
else
    if sudo systemctl restart docker 2>/dev/null; then
        echo "  Docker Engine restarted via sudo systemctl (Docker Engine)"
    else
        echo "  Warning: Could not restart Docker Engine automatically"
        echo "  Run: sudo systemctl restart docker"
    fi
fi

echo "  Waiting for Docker to restart..."
DOCKER_READY=0
for i in $(seq 1 30); do
    if docker info &>/dev/null 2>&1; then
        DOCKER_READY=1
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" -eq 0 ]; then
    echo "  Warning: Docker did not come back within 60s"
    echo "  You may need to wait a moment before the break is fully active"
fi

echo ""
echo "Docker broken"
echo ""
echo "Proxy configuration broken in:"
echo "   - $DOCKER_CONFIG (daemon-level, restart applied)"
echo "   - $SHELL_RC (CLI-level, requires terminal restart or: source $SHELL_RC)"
echo ""

if [ "$DAEMON_BACKUP_CREATED" -eq 1 ] || [ "$SHELL_BACKUP_CREATED" -eq 1 ]; then
    echo "Backups saved:"
    [ "$DAEMON_BACKUP_CREATED" -eq 1 ] && echo "   - ${DOCKER_CONFIG}.backup-${BACKUP_TIMESTAMP}"
    [ "$SHELL_BACKUP_CREATED" -eq 1 ] && echo "   - ${SHELL_RC}.backup-${BACKUP_TIMESTAMP}"
    echo ""
fi

echo "Symptoms: Image pulls fail, container internet access fails"
