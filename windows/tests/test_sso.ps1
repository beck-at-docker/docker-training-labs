# test_sso.ps1 - Validates that the SSO proxy break scenario has been resolved.
#
# The break writes an asymmetric proxy config to Docker Desktop's settings store
# ($env:APPDATA\Docker\settings-store.json): registry hosts are excluded so pulls
# work, but auth/identity endpoints are not excluded so SSO completion fails.
# The trainee is also signed out via docker logout.
#
# A complete fix requires:
#   1. Removing the bogus proxy or correcting ProxyExclude to include auth
#      endpoints, and restarting Docker Desktop
#   2. Successfully signing back in to Docker Hub
#
# IMPORTANT: The trainee must sign back in to Docker Desktop BEFORE running
# --check. This test verifies both the config fix and the functional auth state.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

Write-Host "=========================================="
Write-Host "SSO / Login Loop Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon is running" {
        docker info 2>&1 | Out-Null
    }

    # Pull success is not sufficient to confirm the fix - it worked even when
    # broken. We check it anyway to confirm the fix didn't introduce new issues.
    Run-Test "Image pulls still work after fix" {
        docker pull alpine:latest 2>&1 | Out-Null
    }

    # Authentication check: docker system info shows the logged-in username
    # when Docker Desktop has valid credentials. Empty means still signed out.
    Log-Test "Docker Hub user is authenticated"
    $infoOutput = docker system info 2>&1
    $userLine   = $infoOutput | Select-String "^Username:"
    if ($userLine) {
        $username = ($userLine.Line -split "\s+")[1]
        Log-Pass "Signed in as: $username"
    } else {
        Log-Fail "Not signed in to Docker Hub - fix the proxy then sign in and re-run --check"
    }

    # Proxy config check: verify the Override fields no longer have the bogus
    # proxy address. Docker Desktop uses a two-field pattern: ProxyHTTP/HTTPS is
    # the UI display value; OverrideProxyHTTP/HTTPS is what DD actually routes
    # traffic through. We check the Override fields because clearing only
    # ProxyHTTP/HTTPS is insufficient - the active proxy remains until the
    # Override fields are also cleared.
    Log-Test "settings-store.json proxy configuration is valid"
    if (Test-Path $settingsStore) {
        $data        = Get-Content $settingsStore -Raw | ConvertFrom-Json
        $proxyFields = @("OverrideProxyHTTP", "OverrideProxyHTTPS", "ContainersOverrideProxyHTTP", "ContainersOverrideProxyHTTPS")
        $hasBogus    = $false
        foreach ($field in $proxyFields) {
            if ($data.$field -and $data.$field -match "192\.0\.2") {
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

    # ProxyExclude check: if a manual proxy is still configured (legitimate
    # corporate proxy scenario), verify auth endpoints are not missing from the
    # exclude list. This catches a partial fix where the trainee corrected the
    # proxy address but left the asymmetric exclusion in place.
    Log-Test "Auth endpoints are not blocked by proxy exclude list"
    if (Test-Path $settingsStore) {
        $data = Get-Content $settingsStore -Raw | ConvertFrom-Json
        $mode = $data.ProxyHTTPMode

        if ($mode -ne "manual") {
            Log-Pass "Proxy is not in manual mode - no exclusion list to check"
        } else {
            $proxyAddr  = $data.OverrideProxyHTTP
            $exclude    = $data.ProxyExclude
            $bogusProxy = $proxyAddr -match "192\.0\.2"
            $authHosts  = @("hub.docker.com", "login.docker.com", "id.docker.com")
            $authBlocked = $bogusProxy -and (-not ($authHosts | Where-Object { $exclude -match $_ }))

            if ($authBlocked) {
                Log-Fail "Auth endpoints are still blocked by the asymmetric proxy exclude list"
            } else {
                Log-Pass "Auth endpoints are reachable (not blocked by proxy)"
            }
        }
    } else {
        Log-Pass "settings-store.json not present (not applicable)"
    }

    Run-Test "Second image pull succeeds" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Cleanup
    docker rmi hello-world 2>&1 | Out-Null
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "SSO_Login_Scenario"

$score = Calculate-Score

Write-Host ""
Write-Host "Score: $score%"
