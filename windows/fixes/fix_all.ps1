# fix_all.ps1 - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=========================================="
Write-Host "Restoring ALL Docker Desktop Systems"
Write-Host "=========================================="
Write-Host ""
Write-Host "This will fix:"
Write-Host "  1. DNS Resolution"
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -notmatch "^[yY]$") {
    Write-Host "Cancelled."
    exit 0
}

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "[1/1] Fixing DNS Resolution..."
& "$SCRIPT_DIR\fix_dns.ps1"

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
