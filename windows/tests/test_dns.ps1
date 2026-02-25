# test_dns.ps1 - Validates that the DNS break scenario has been resolved.
#
# The break injects iptables DROP rules for port 53 into the Docker Desktop VM,
# preventing the Docker daemon from resolving external hostnames. The symptom
# is that docker pull fails with "write: operation not permitted" on a DNS
# socket write.
#
# A complete fix requires removing the DROP rules from the VM's OUTPUT chain
# via nsenter. Restarting Docker Desktop also clears the rules (ephemeral VM)
# and is accepted as a valid last resort.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

Write-Host "=========================================="
Write-Host "DNS Resolution Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    # Primary functional test: the daemon must be able to resolve registry
    # hostnames. This is the operation the break actually broke.
    Run-Test "docker pull succeeds (daemon DNS is working)" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Stability: confirm it is not a one-off success
    Run-Test "docker pull succeeds a second time" {
        docker pull alpine:latest 2>&1 | Out-Null
    }

    # Root cause check: verify the DROP rules have been removed from OUTPUT.
    Log-Test "iptables DROP rules for port 53 have been removed"
    $remainingRules = docker run --rm --privileged --pid=host alpine:latest `
        nsenter -t 1 -m -u -n -i sh -c `
        'iptables -L OUTPUT -n 2>/dev/null | grep -c "dpt:53" || true' 2>&1 | Out-String
    $remainingRules = $remainingRules.Trim()
    if ($remainingRules -eq "0" -or $remainingRules -eq "") {
        Log-Pass "iptables DROP rules for port 53 have been removed"
    } else {
        Log-Fail "iptables DROP rules for port 53 are still present ($remainingRules rule(s) found)"
    }
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "DNS_Scenario"

$score = Calculate-Score
Write-Host ""
# Parsed by Check-Lab in troubleshootwinlab.ps1. Format must stay: "Score: <n>%"
Write-Host "Score: $score%"

if ($score -ge 90)    { Write-Host "Grade: A - Excellent work!" }
elseif ($score -ge 80){ Write-Host "Grade: B - Good job!" }
elseif ($score -ge 70){ Write-Host "Grade: C - Passing" }
else                  { Write-Host "Grade: F - Needs improvement" }

Write-Host ""
Write-Host "Score: $score%"
Write-Host "Tests Passed: $script:TESTS_PASSED"
Write-Host "Tests Failed: $script:TESTS_FAILED"
