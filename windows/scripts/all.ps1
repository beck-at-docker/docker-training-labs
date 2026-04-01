# all.ps1 - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=========================================="
Write-Host "Restoring ALL Docker Desktop Systems"
Write-Host "=========================================="
Write-Host ""
Write-Host "This will fix:"
Write-Host "  1. Bridge Network"
Write-Host "  2. DNS Resolution"
Write-Host "  3. Proxy Configuration"
Write-Host "  4. Proxy Failure Simulation"
Write-Host "  5. SSO Configuration"
Write-Host "  6. Auth Config Enforcement"
Write-Host "  7. Port Conflicts"
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -notmatch "^[yY]$") {
    Write-Host "Cancelled."
    exit 0
}

Write-Host ""
Write-Host "=========================================="
Write-Host ""
# Fix bridge first (iptables rules affect all container networking),
# then DNS, then proxy variants, then SSO and authconfig
# (settings-store.json changes), ports last.
Write-Host "[1/7] Fixing Bridge Network..."
& "$SCRIPT_DIR\bridge.ps1"
if ($LASTEXITCODE -ne 0) { throw "bridge.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[2/7] Fixing DNS Resolution..."
& "$SCRIPT_DIR\dns.ps1"
if ($LASTEXITCODE -ne 0) { throw "dns.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[3/7] Fixing Proxy Configuration..."
& "$SCRIPT_DIR\proxy.ps1"
if ($LASTEXITCODE -ne 0) { throw "proxy.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[4/7] Fixing Proxy Failure Simulation..."
& "$SCRIPT_DIR\proxyfail.ps1"
if ($LASTEXITCODE -ne 0) { throw "proxyfail.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[5/7] Fixing SSO Configuration..."
& "$SCRIPT_DIR\sso.ps1"
if ($LASTEXITCODE -ne 0) { throw "sso.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[6/7] Fixing Auth Config Enforcement..."
& "$SCRIPT_DIR\authconfig.ps1"
if ($LASTEXITCODE -ne 0) { throw "authconfig.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[7/7] Fixing Port Conflicts..."
& "$SCRIPT_DIR\ports.ps1"
if ($LASTEXITCODE -ne 0) { throw "ports.ps1 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "=========================================="
Write-Host "All Systems Restored"
Write-Host "=========================================="
Write-Host ""
Write-Host "IMPORTANT: Restart Docker Desktop for all changes to take effect!"
Write-Host ""
Write-Host "To restart Docker Desktop:"
Write-Host "  1. Right-click the Docker icon in your taskbar"
Write-Host "  2. Select 'Restart'"
Write-Host "  3. Wait for Docker Desktop to fully restart"
Write-Host ""
Write-Host "After Docker restarts, verify everything works:"
Write-Host "  docker run --rm alpine:latest ping -c 2 google.com"
Write-Host "  docker pull hello-world"
Write-Host ""
