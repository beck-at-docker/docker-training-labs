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
    #
    # Variable capture: PowerShell scriptblocks do not automatically capture
    # foreach-scope variables. We use .GetNewClosure() to snapshot $capturedPort
    # at each iteration so the block sees the right value when Run-Test calls it.
    # Without this, $port would be $null inside every block.
    #
    # 'throw' is used instead of 'exit' to signal failure. 'exit' inside a
    # scriptblock called with & terminates the entire PowerShell session.
    # Run-Test's try/catch converts a thrown exception into a test failure.
    #
    # Pre-clean any test containers left over from an interrupted previous run
    # to avoid false failures caused by name conflicts rather than port conflicts.
    $ports = @(80, 443, 3306, 5432, 8080)
    foreach ($port in $ports) {
        docker rm -f "test-port-$port" 2>&1 | Out-Null

        $capturedPort = $port
        $testBlock = {
            docker run -d --name "test-port-$capturedPort" -p "${capturedPort}:80" nginx:alpine 2>&1 | Out-Null
            $runExitCode = $LASTEXITCODE
            docker rm -f "test-port-$capturedPort" 2>&1 | Out-Null
            if ($runExitCode -ne 0) { throw "Port $capturedPort is still occupied" }
        }.GetNewClosure()

        Run-Test "Port $port is available" $testBlock
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
    # Check both the saved job ID file and whether anything is still
    # listening on 8080 at the process level.
    Log-Test "Background TCP listener on port 8080 stopped"
    $listenerRunning = $false

    Log-Test "Job ID file cleaned up"
    if (Test-Path $jobIdFile) {
        $jobId = Get-Content $jobIdFile -ErrorAction SilentlyContinue
        if ($jobId) {
            $job = Get-Job -Id $jobId -ErrorAction SilentlyContinue
            if ($job -and $job.State -eq "Running") {
                $listenerRunning = $true
            }
        }
        Log-Fail "Job ID file still exists at $jobIdFile"
    } else {
        Log-Pass "Job ID file cleaned up"
    }

    $netstatResult = netstat -ano 2>&1 | Select-String ":8080.*LISTENING"
    if ($netstatResult -or $listenerRunning) {
        Log-Fail "Something is still listening on port 8080"
    } else {
        Log-Pass "Background TCP listener on port 8080 stopped"
    }

    # Stability: confirm ports can be allocated and freed repeatedly.
    # Pre-clean in case containers from a previous interrupted run remain.
    docker rm -f rapid-test-1 rapid-test-2 rapid-test-3 2>&1 | Out-Null
    Run-Test "Can rapidly allocate and free ports" {
        for ($i = 1; $i -le 3; $i++) {
            docker run -d --name "rapid-test-$i" -p "8080:80" nginx:alpine 2>&1 | Out-Null
            $runCode = $LASTEXITCODE
            docker rm -f "rapid-test-$i" 2>&1 | Out-Null
            if ($runCode -ne 0) { throw "Failed to allocate port 8080 on iteration $i" }
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
