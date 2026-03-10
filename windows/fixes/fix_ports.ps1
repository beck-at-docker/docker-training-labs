# fixes/fix_ports.ps1 - Clean up port squatter containers and background job
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# After repairing the environment, this script also resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no active lab.

$ErrorActionPreference = "Stop"

$jobIdFile = "$env:TEMP\port_squatter_8080_job.txt"

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

Write-Host "Cleaning up port conflicts..."

# Remove all port squatter containers
Write-Host "Removing port squatter containers..."
$containers = @("port-squatter-80", "port-squatter-443", "port-squatter-3306", "background-db")
foreach ($name in $containers) {
    docker rm -f $name 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  Removed $name" }
}

# Stop and remove the background TcpListener job
Write-Host ""
Write-Host "Stopping background TCP listener on port 8080..."
if (Test-Path $jobIdFile) {
    $jobId = Get-Content $jobIdFile -ErrorAction SilentlyContinue
    if ($jobId) {
        Stop-Job  -Id $jobId -ErrorAction SilentlyContinue
        Remove-Job -Id $jobId -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped job $jobId"
    }
    Remove-Item $jobIdFile -ErrorAction SilentlyContinue
    Write-Host "  Removed job ID file"
} else {
    Write-Host "  No job ID file found - checking for orphaned TcpListener jobs..."
    # Narrow scope: only stop jobs whose command block contains TcpListener,
    # which is the signature of the port squatter job. Killing all running
    # jobs would affect any other background work the instructor has running.
    Get-Job | Where-Object { $_.State -eq "Running" -and $_.Command -like "*TcpListener*" } | ForEach-Object {
        Stop-Job  -Id $_.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped orphaned TcpListener job $($_.Id)"
    }
}

Write-Host ""
Write-Host "Port cleanup complete"

# Reset the lab state last, after the environment is repaired.
Reset-LabState
Write-Host "Lab state reset: no active scenario"
