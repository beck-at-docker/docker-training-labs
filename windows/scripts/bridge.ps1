# bridge.ps1 - Restore Docker bridge network
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# After repairing the environment, this script also resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no active lab.

$ErrorActionPreference = "Stop"

# Reset the training lab state file so the CLI sees no active scenario.
# Mirrors the logic in lib/state.ps1 without requiring it to be dot-sourced.
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
    $data | ConvertTo-Json | Set-Content $configFile -Encoding UTF8
}

Write-Host "Restoring Docker bridge network..."

# Remove test containers
Write-Host "Removing test containers..."
docker rm -f broken-web 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  Removed broken-web" }
docker rm -f broken-app 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  Removed broken-app" }

# Remove the DROP rule injected by break_bridge.ps1. The Docker chain rules
# are untouched by the break and do not need to be restored.
Write-Host ""
Write-Host "Restoring iptables rules..."
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c '
    iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true
    echo "DROP rule removed"
'
if ($LASTEXITCODE -ne 0) {
    Write-Host "  iptables restore failed - restarting Docker Desktop is recommended"
}

# Verify the fix
Write-Host ""
Write-Host "Verifying network connectivity..."
docker run --rm alpine:latest ping -c 2 8.8.8.8 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Internet connectivity working"
} else {
    Write-Host "  Internet connectivity still broken"
}

docker run --rm alpine:latest ping -c 2 google.com 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  DNS resolution working"
} else {
    Write-Host "  DNS still broken"
}

Write-Host ""
Write-Host "Bridge network restoration complete"
Write-Host ""
Write-Host "If issues persist, restart Docker Desktop:"
Write-Host "  1. Click Docker whale icon in system tray"
Write-Host "  2. Select 'Restart'"

Reset-LabState
Write-Host "Lab state reset: no active scenario"
