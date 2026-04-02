# test_authconfig.ps1 - Validates that the allowedOrgs misconfiguration
# has been resolved.
#
# The break writes a URL-format value to the allowedOrgs key in Docker
# Desktop's settings store ($env:APPDATA\Docker\settings-store.json). Docker
# Desktop's org enforcement check matches against plain slugs only - a URL
# value never matches any real org, so every sign-in attempt is immediately
# rejected.
#
# A complete fix requires:
#   1. Correcting allowedOrgs to use a plain slug (or removing the key
#      entirely) in settings-store.json and restarting Docker Desktop
#   2. Successfully signing back in to Docker Hub
#
# IMPORTANT: The trainee must sign back in to Docker Desktop BEFORE running
# --check. This test verifies both the config fix and the restored auth state.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

Write-Host "=========================================="
Write-Host "Auth Config (allowedOrgs) Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon is running" {
        docker info 2>&1 | Out-Null
    }

    # Primary config check: allowedOrgs must not contain URL-format values.
    # Docker Desktop expects plain org slugs (e.g. "my-company"). Any value
    # starting with "https://" is definitively wrong regardless of the org name.
    # Valid fixed states: key absent, empty array, or a plain-slug array.
    Log-Test "allowedOrgs does not contain URL-format values"
    if (Test-Path $settingsStore) {
        $data   = Get-Content $settingsStore -Raw | ConvertFrom-Json
        $orgs   = $data.allowedOrgs
        $hasBad = $false
        if ($orgs) {
            foreach ($org in $orgs) {
                if ($org -match "^https?://") {
                    $hasBad = $true
                    break
                }
            }
        }
        if ($hasBad) {
            Log-Fail "allowedOrgs still contains a URL-format value - should be a plain org slug or empty"
        } else {
            Log-Pass "allowedOrgs contains no URL-format values"
        }
    } else {
        Log-Pass "settings-store.json not present (not applicable)"
    }

    # Authentication check: the trainee must have signed back in after fixing
    # the config. An empty username means the config may be fixed but step two
    # (re-authenticating) has not been completed.
    Log-Test "Docker Hub user is authenticated"
    $infoOutput = docker system info 2>&1
    $userLine   = $infoOutput | Select-String "^Username:"
    if ($userLine) {
        $username = ($userLine.Line -split "\s+")[1]
        Log-Pass "Signed in as: $username"
    } else {
        Log-Fail "Not signed in to Docker Hub - fix the config, sign in, then re-run --check"
    }

    # Functional verification: confirm registry access is healthy after the fix.
    # The break does not directly block pulls (anonymous access still works),
    # but this confirms Docker Desktop is in a clean state.
    Run-Test "Can pull images from Docker Hub" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Cleanup
    docker rmi hello-world 2>&1 | Out-Null
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "AuthConfig_Scenario"

$score = Calculate-Score

Write-Host ""
Write-Host "Score: $score%"
