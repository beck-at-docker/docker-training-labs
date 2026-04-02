# test_bridge.ps1 - Validates that the bridge network corruption scenario
# has been resolved.
#
# The break inserts a DROP rule at the top of the iptables FORWARD chain for
# all traffic from docker0. Containers start and get IPs normally (the control
# plane is untouched) but data-plane forwarding is blocked, so containers
# cannot reach each other or the internet.
#
# The iptables rules live inside the Docker Desktop VM (WSL2 or Hyper-V
# backend), not on the Windows host. The nsenter privileged container is
# required to inspect and remove them.
#
# A complete fix requires removing the DROP rule from the FORWARD chain.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

Write-Host "=========================================="
Write-Host "Bridge Network Corruption Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon is running" {
        docker info 2>&1 | Out-Null
    }

    Run-Test "Container can reach internet (IP)" {
        docker run --rm alpine:latest ping -c 3 8.8.8.8 2>&1 | Out-Null
    }

    Run-Test "Container can reach internet (hostname)" {
        docker run --rm alpine:latest ping -c 3 google.com 2>&1 | Out-Null
    }

    # Test container-to-container communication by starting a target container,
    # fetching its assigned IP, and pinging it from a separate container.
    docker run -d --name test-web-fixed nginx:alpine 2>&1 | Out-Null
    Start-Sleep -Seconds 2  # wait for the container's network interface to be assigned an IP

    $webIp = (docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test-web-fixed 2>&1).Trim()

    Log-Test "Container-to-container communication restored"
    if ($webIp) {
        docker run --rm alpine:latest ping -c 2 $webIp 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Log-Pass "Container-to-container communication restored"
        } else {
            Log-Fail "Container-to-container ping failed (target: $webIp)"
        }
    } else {
        Log-Fail "Could not get container IP - container may not have started"
    }

    docker rm -f test-web-fixed 2>&1 | Out-Null

    # Verify iptables FORWARD chain has no DROP rule for docker0.
    # nsenter is required because iptables rules live inside the Docker Desktop
    # VM (WSL2 or Hyper-V), not on the Windows host.
    $forwardRules = docker run --rm --privileged --pid=host alpine:latest `
        nsenter -t 1 -m -u -n -i iptables -L FORWARD -n 2>&1

    Log-Test "Docker iptables chains present"
    if ($forwardRules -match "DOCKER") {
        Log-Pass "Docker iptables chains present"
    } else {
        Log-Fail "Docker iptables chains may be missing"
    }

    Log-Test "No blocking DROP rule for docker0 in FORWARD chain"
    if ($forwardRules -notmatch "DROP.*docker0") {
        Log-Pass "No blocking DROP rule found for docker0"
    } else {
        Log-Fail "DROP rule for docker0 still present in FORWARD chain"
    }

    # Clean up the test containers left behind by the break script
    docker rm -f broken-web broken-app 2>&1 | Out-Null
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "Bridge_Network_Scenario"

$score = Calculate-Score

Write-Host ""
Write-Host "Score: $score%"
