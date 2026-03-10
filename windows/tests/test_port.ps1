# tests/test_port.ps1 - Validates that the port binding conflict scenario has been resolved.
#
# The break occupies five ports with a mix of Docker containers and a background
# PowerShell job running a TcpListener on port 8080. A complete fix requires
# removing all squatter containers and stopping the background job.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$jobIdFile = "$env:TEMP\port_squatter_8080_job.txt"

Write-Host "=========================================="
Write-Host "Port Binding Conflicts Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon running after fix" {
        docker info 2>&1 | Out-Null
    }

    # Verify each port is free by binding a temporary container to it.
    # All five are tested individually so trainees can see exactly which
    # ports are still occupied if the fix was incomplete.
    $ports = @(80, 443, 3306, 5432, 8080)
    foreach ($port in $ports) {
        Run-Test "Port $port is available" {
            docker run -d --name "test-port-$port" -p "${port}:80" nginx:alpine 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { exit 1 }
            docker rm -f "test-port-$port" 2>&1 | Out-Null
        }
    }

    # Verify all squatter containers have been removed
    Log-Test "All port squatter containers removed"
    $squatters = docker ps -a --filter "name=port-squatter" --filter "name=background-db" --format "{{.Names}}" 2>&1
    if (-not $squatters) {
        Log-Pass "All port squatter containers removed"
    } else {
        Log-Fail "Still found squatter containers: $squatters"
    }

    # Verify the background TcpListener job is no longer running.
    # Check both the saved job ID (if the file exists) and whether anything
    # is still listening on 8080 at the process level.
    Log-Test "Background TCP listener on port 8080 stopped"
    $listenerRunning = $false

    if (Test-Path $jobIdFile) {
        $jobId = Get-Content $jobIdFile -ErrorAction SilentlyContinue
        if ($jobId) {
            $job = Get-Job -Id $jobId -ErrorAction SilentlyContinue
            if ($job -and $job.State -eq "Running") {
                $listenerRunning = $true
            }
        }
        # Job ID file still present counts as incomplete cleanup
        Log-Test "Job ID file cleaned up"
        Log-Fail "Job ID file still exists at $jobIdFile"
    } else {
        Log-Test "Job ID file cleaned up"
        Log-Pass "Job ID file cleaned up"
    }

    # Also check via netstat whether anything is listening on 8080
    $netstatResult = netstat -ano 2>&1 | Select-String ":8080.*LISTENING"
    if ($netstatResult -or $listenerRunning) {
        Log-Fail "Something is still listening on port 8080"
    } else {
        Log-Pass "Background TCP listener on port 8080 stopped"
    }

    # Stability: confirm ports can be allocated and freed repeatedly
    Run-Test "Can rapidly allocate and free ports" {
        for ($i = 1; $i -le 3; $i++) {
            docker run -d --name "rapid-test-$i" -p "8080:80" nginx:alpine 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { exit 1 }
            docker rm -f "rapid-test-$i" 2>&1 | Out-Null
        }
    }
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "Port_Conflicts_Scenario"

$score = Calculate-Score

# Only Score: is written here. Tests Passed: and Tests Failed: are written
# by Generate-Report above.
Write-Host ""
Write-Host "Score: $score%"
