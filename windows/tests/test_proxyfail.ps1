# test_proxyfail.ps1 - Validates that the loopback proxy misconfiguration
# has been resolved.
#
# The break writes a manual proxy pointing to 127.0.0.1:9753 into Docker
# Desktop's settings store ($env:APPDATA\Docker\settings-store.json). Unlike
# the PROXY lab which uses a non-routable RFC 5737 address (192.0.2.1) that
# silently drops packets, this break uses a loopback address that produces
# immediate "connection refused" errors - the key diagnostic distinction this
# lab teaches.
#
# A complete fix requires removing the loopback proxy from settings-store.json
# (either clearing the manual proxy keys or switching ProxyHTTPMode back to
# "system") and restarting Docker Desktop.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

# The specific loopback address written by break_proxyfail.ps1
$brokenProxy = "127.0.0.1:9753"

Write-Host "=========================================="
Write-Host "Proxy Connection Refused Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon is running" {
        docker info 2>&1 | Out-Null
    }

    Run-Test "Can pull images from Docker Hub" {
        docker pull alpine:latest 2>&1 | Out-Null
    }

    Run-Test "Containers can reach the internet" {
        docker run --rm alpine:latest wget -q -O- https://google.com 2>&1 | Out-Null
    }

    # Check that settings-store.json no longer references the loopback proxy.
    # The break script sets all four proxy fields (daemon-level and
    # container-level, HTTP and HTTPS), so we check them all.
    Log-Test "settings-store.json does not contain the broken loopback proxy"
    if (Test-Path $settingsStore) {
        $data        = Get-Content $settingsStore -Raw | ConvertFrom-Json
        $proxyFields = @("ProxyHTTP", "ProxyHTTPS", "ContainersProxyHTTP", "ContainersProxyHTTPS")
        $hasBroken   = $false
        foreach ($field in $proxyFields) {
            # Use regex escape so the dots and colon in the address are treated
            # literally and not as regex metacharacters
            if ($data.$field -and $data.$field -match [regex]::Escape($brokenProxy)) {
                $hasBroken = $true
                break
            }
        }
        if ($hasBroken) {
            Log-Fail "settings-store.json still contains the broken proxy (127.0.0.1:9753)"
        } else {
            Log-Pass "settings-store.json has no loopback proxy address"
        }
    } else {
        Log-Pass "settings-store.json not present (not applicable)"
    }

    # Stability check: a second pull confirms the fix is not transient
    Run-Test "Second pull succeeds" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Cleanup
    docker rmi hello-world 2>&1 | Out-Null
    docker rmi alpine:latest 2>&1 | Out-Null
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "ProxyFail_Scenario"

$score = Calculate-Score

Write-Host ""
Write-Host "Score: $score%"
