# dns.ps1 - Restore Docker daemon DNS resolution in Docker Desktop
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# The DNS break injects two iptables DROP rules for port 53 into the Docker
# Desktop VM's OUTPUT chain via nsenter. This script removes those rules
# using the same mechanism.
#
# After repairing the environment, this script also resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no active lab.

$ErrorActionPreference = "Stop"

# Reset the training lab state file so the CLI sees no active scenario.
# Mirrors the logic in lib/state.ps1 without requiring it to be dot-sourced.
# Uses Add-Member -Force to set properties on the PSCustomObject, which is
# required in PS5.1 (direct property assignment on ConvertFrom-Json objects
# is unreliable).
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

Write-Host "Fixing Docker Desktop DNS..."

# Verify Docker Desktop is running before attempting anything
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

# Remove the DROP rules for port 53 (UDP and TCP) from the VM's OUTPUT chain.
# -D deletes the first matching rule; run once per protocol to match the two
# rules injected by break_dns.ps1.
# Use a semicolon-delimited string - PS5.1 argument passing to external
# commands is unreliable with newlines in strings.
$iptablesCmd = "iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true; " +
               "iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true"

docker run --rm --privileged --pid=host alpine:latest `
    nsenter -t 1 -m -u -n -i sh -c $iptablesCmd 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to access the Docker VM via nsenter"
    exit 1
}

# Verify the fix
Write-Host ""
Write-Host "Verifying DNS resolution..."
docker pull hello-world 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "DNS resolution working"
    docker rmi hello-world 2>&1 | Out-Null
} else {
    Write-Host "DNS still broken - may need Docker Desktop restart"
}

# Reset the lab state last, after the environment is repaired.
Reset-LabState
Write-Host "Lab state reset: no active scenario"
