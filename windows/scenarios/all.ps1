# all.ps1 - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Dot-sources lib/fix.ps1 for individual scenario fix functions, then runs all
# of them in the correct order, performs a single Docker Desktop restart, and
# prints a clear pass/fail summary.

# Dot-source shared fix functions ($settingsStore, $dockerExe, Stop-DockerDesktop, Fix-*)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\lib\fix.ps1"

# ===========================================================================
# Shared helpers
# ===========================================================================

# Reset-LabState - Clear the active scenario from config.json.
# Called once at the end after all fixes have been applied.
function Reset-LabState {
    $configFile = Join-Path $HOME ".docker-training-labs\config.json"
    if (-not (Test-Path $configFile)) { return }
    try {
        $data = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        $data = [PSCustomObject]@{}
    }
    $data | Add-Member -MemberType NoteProperty -Name current_scenario    -Value $null -Force
    $data | Add-Member -MemberType NoteProperty -Name scenario_start_time -Value $null -Force
    Write-JsonFile -Path $configFile -Content ($data | ConvertTo-Json)
}

# Invoke-Section <label> <scriptblock>
# Runs the given scriptblock, tracks pass/fail, never exits early.
function Invoke-Section {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "--- $Label ---"
    try {
        & $Action
        Write-Host "  -> OK"
    }
    catch {
        Write-Host "  -> FAILED: $_"
        $script:failedSteps += $Label
    }
    Write-Host ""
    Write-Host "=========================================="
}

# ===========================================================================
# Main
# ===========================================================================

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

# ------------------------------------------------------------------
# Phase 1: fixes that require Docker to be running.
#
# Bridge and DNS inject iptables rules inside the VM via nsenter, which
# requires a running daemon. Port cleanup uses docker rm. Proxy,
# ProxyFail, and SSO use the Docker Desktop backend pipe API, which also
# requires a running daemon. All six must run before Docker Desktop is
# stopped.
# ------------------------------------------------------------------
Invoke-Section "[1/7] Bridge Network"           { Fix-Bridge }
Invoke-Section "[2/7] DNS Resolution"           { Fix-Dns }
Invoke-Section "[3/7] Proxy Configuration"      { Fix-Proxy }
Invoke-Section "[4/7] Proxy Failure Simulation" { Fix-ProxyFail }
Invoke-Section "[5/7] SSO Configuration"        { Fix-Sso }
Invoke-Section "[7/7] Port Conflicts"           { Fix-Ports }

# ------------------------------------------------------------------
# Phase 2: fixes that write to settings-store.json.
#
# AUTHCONFIG writes allowedOrgs to the settings file. Docker Desktop
# must be stopped first so its graceful-shutdown flush does not
# overwrite the changes.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Stopping Docker Desktop ---"
Write-Host ""

Stop-DockerDesktop
Write-Host ""
Write-Host "=========================================="

Invoke-Section "[6/7] Auth Config Enforcement"  { Fix-AuthConfig }

# ------------------------------------------------------------------
# Relaunch Docker Desktop with the corrected settings.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Restarting Docker Desktop ---"
Write-Host ""

if (Test-Path $dockerExe) {
    Start-Process $dockerExe
} else {
    Write-Host "  Warning: Could not find Docker Desktop.exe - please start it manually"
    $failedSteps += "Docker Desktop restart"
}

Write-Host "Waiting for Docker Desktop to restart..."
$dockerReady = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
        break
    }
}

if (-not $dockerReady) {
    Write-Host "  Warning: Docker Desktop did not come back within 120s"
    $failedSteps += "Docker Desktop restart"
} else {
    Write-Host "  Docker Desktop is running"
    Write-Host ""
    Write-Host "Verifying registry access..."
    docker pull hello-world 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Registry access working"
        docker rmi hello-world 2>&1 | Out-Null
    } else {
        Write-Host "  Registry access not working - check Docker Desktop status"
        $failedSteps += "Registry access verification"
    }
}

Write-Host ""
Write-Host "=========================================="

# Clear lab state now that all fixes have been applied.
Reset-LabState
Write-Host "Lab state reset: no active scenario"

Write-Host ""
Write-Host "=========================================="

if ($failedSteps.Count -eq 0) {
    Write-Host "All Systems Restored"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Docker Desktop has been restarted. Verify everything is working:"
    Write-Host "  docker pull hello-world"
    Write-Host "  docker run --rm alpine:latest ping -c 2 google.com"
    Write-Host "  docker run -p 8080:80 nginx:alpine"
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
