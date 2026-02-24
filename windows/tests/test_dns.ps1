# test_dns.ps1 - Test DNS break/fix scenario

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

Write-Host "=========================================="
Write-Host "DNS Resolution Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon running after fix" {
        docker info 2>&1 | Out-Null
    }

    Run-Test "Container DNS resolution works" {
        docker run --rm alpine:latest nslookup google.com 2>&1 | Out-Null
    }

    Run-Test "Container can ping external hostname" {
        docker run --rm alpine:latest ping -c 2 google.com 2>&1 | Out-Null
    }

    # Check that no DROP rules remain for port 53 in OUTPUT chain
    Log-Test "No blocking iptables rules for DNS in OUTPUT chain"
    $rules = docker run --rm --privileged --pid=host alpine:latest `
        nsenter -t 1 -m -u -n -i sh -c 'iptables -L OUTPUT -n' 2>&1 | Out-String
    if ($rules -match "DROP.*dpt:53") {
        Log-Fail "DROP rules for port 53 still present in OUTPUT chain"
    } else {
        Log-Pass "No DROP rules blocking DNS in OUTPUT chain"
    }

    # Check FORWARD chain too
    Log-Test "No blocking iptables rules for DNS in FORWARD chain"
    $fwdRules = docker run --rm --privileged --pid=host alpine:latest `
        nsenter -t 1 -m -u -n -i sh -c 'iptables -L FORWARD -n' 2>&1 | Out-String
    if ($fwdRules -match "DROP.*dpt:53") {
        Log-Fail "DROP rules for port 53 still present in FORWARD chain"
    } else {
        Log-Pass "No DROP rules blocking DNS in FORWARD chain"
    }

    # Stability check - use throw instead of exit so Run-Test catches the failure
    # cleanly without killing the test process
    Run-Test "Multiple DNS queries work (stability check)" {
        $failed = $false
        1..5 | ForEach-Object {
            docker run --rm alpine:latest nslookup google.com 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        }
        if ($failed) { throw "One or more DNS queries failed" }
    }
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "DNS_Scenario"

$score = Calculate-Score
Write-Host ""
Write-Host "Score: $score%"

if ($score -ge 90)    { Write-Host "Grade: A - Excellent work!" -ForegroundColor Green }
elseif ($score -ge 80){ Write-Host "Grade: B - Good job!" -ForegroundColor Green }
elseif ($score -ge 70){ Write-Host "Grade: C - Passing" -ForegroundColor Yellow }
else                  { Write-Host "Grade: F - Needs improvement" -ForegroundColor Red }

# Structured output for Check-Lab to parse
Write-Host ""
Write-Host "Score: $score%"
Write-Host "Tests Passed: $script:TESTS_PASSED"
Write-Host "Tests Failed: $script:TESTS_FAILED"
