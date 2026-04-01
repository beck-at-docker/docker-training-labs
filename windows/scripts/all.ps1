# all.ps1 - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

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

# Tracks which steps failed so we can report clearly at the end.
$failedSteps = @()

# Invoke-Fix runs the given fix script and records pass/fail. Never exits early.
function Invoke-Fix {
    param(
        [string]$Label,
        [string]$Script
    )

    Write-Host ""
    Write-Host "--- $Label ---"
    try {
        & "$SCRIPT_DIR\$Script"
        if ($LASTEXITCODE -ne 0) {
            throw "Exit code $LASTEXITCODE"
        }
        Write-Host "  -> OK"
    }
    catch {
        Write-Host "  -> FAILED: $_"
        $script:failedSteps += $Label
    }
    Write-Host ""
    Write-Host "=========================================="
}

# Fix bridge first (iptables rules affect all container networking),
# then DNS, then proxy variants, then SSO and authconfig
# (settings-store.json changes), ports last.
Invoke-Fix "[1/7] Bridge Network"           "bridge.ps1"
Invoke-Fix "[2/7] DNS Resolution"           "dns.ps1"
Invoke-Fix "[3/7] Proxy Configuration"      "proxy.ps1"
Invoke-Fix "[4/7] Proxy Failure Simulation" "proxyfail.ps1"
Invoke-Fix "[5/7] SSO Configuration"        "sso.ps1"
Invoke-Fix "[6/7] Auth Config Enforcement"  "authconfig.ps1"
Invoke-Fix "[7/7] Port Conflicts"           "ports.ps1"

Write-Host ""
Write-Host "=========================================="

if ($failedSteps.Count -eq 0) {
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
    exit 0
} else {
    Write-Host "Restore completed with errors"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "The following steps failed:"
    foreach ($step in $failedSteps) {
        Write-Host "  - $step"
    }
    Write-Host ""
    Write-Host "Review the output above for details on each failure."
    Write-Host ""
    exit 1
}
