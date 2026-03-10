# test_proxy.ps1 - Validates that the proxy break scenario has been resolved.
#
# The break writes bogus proxy config into Docker Desktop's settings store
# ($env:APPDATA\Docker\settings-store.json) and sets HTTP_PROXY / HTTPS_PROXY
# in the User-scope environment (HKCU:\Environment).
#
# A complete fix requires:
#   1. Restoring the settings store to a valid proxy config and restarting
#      Docker Desktop
#   2. Clearing the User-scope proxy environment variables
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

Write-Host "=========================================="
Write-Host "Proxy Configuration Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    # Primary functional tests: image pulls and container internet access
    # are the two operations most visibly broken by proxy misconfiguration.
    Run-Test "Can pull images from Docker Hub" {
        docker pull alpine:latest 2>&1 | Out-Null
    }

    Run-Test "Containers can reach the internet" {
        docker run --rm alpine:latest wget -q -O- https://google.com 2>&1 | Out-Null
    }

    # Check that the settings store no longer has the bogus proxy address.
    # This is the authoritative proxy config on Windows Docker Desktop.
    Log-Test "settings-store.json proxy configuration is valid"
    if (Test-Path $settingsStore) {
        $data = Get-Content $settingsStore -Raw | ConvertFrom-Json
        $proxyFields = @("ProxyHTTP", "ProxyHTTPS", "ContainersProxyHTTP", "ContainersProxyHTTPS")
        $hasBogus = $false
        foreach ($field in $proxyFields) {
            $val = $data.$field
            if ($val -and ($val -match "192\.0\.2" -or $val -match "invalid")) {
                $hasBogus = $true
                break
            }
        }
        if ($hasBogus) {
            Log-Fail "settings-store.json still contains the bogus proxy (192.0.2.x)"
        } else {
            Log-Pass "settings-store.json has no invalid proxy addresses"
        }
    } else {
        Log-Pass "settings-store.json not present (not applicable)"
    }

    # Check that User-scope environment variables are not set to the broken values.
    # A legitimate corporate proxy is acceptable; the training lab's specific
    # unroutable address (192.0.2.x, RFC 5737 TEST-NET) is not.
    Log-Test "User-scope proxy environment variables are valid"
    $httpProxy  = [System.Environment]::GetEnvironmentVariable("HTTP_PROXY",  "User")
    $httpsProxy = [System.Environment]::GetEnvironmentVariable("HTTPS_PROXY", "User")
    $combined   = "$httpProxy$httpsProxy"
    if ($combined -match "192\.0\.2|invalid") {
        Log-Fail "User-scope proxy variables still contain the bogus address"
    } elseif ($httpProxy) {
        Log-Pass "User-scope proxy variables point to a valid proxy"
    } else {
        Log-Pass "No User-scope proxy variables set (direct internet access)"
    }

    # Stability: confirm functionality is not a one-off success.
    Run-Test "Multiple image pulls succeed" {
        docker pull hello-world 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { exit 1 }
        docker pull busybox 2>&1 | Out-Null
    }

    # Cleanup
    docker rmi hello-world busybox 2>&1 | Out-Null
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "Proxy_Configuration_Scenario"

$score = Calculate-Score

# Only Score: is written here. Tests Passed: and Tests Failed: are written
# by Generate-Report above. Writing them again would cause Check-Lab to
# parse duplicate lines.
Write-Host ""
Write-Host "Score: $score%"
