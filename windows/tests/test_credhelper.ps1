# tests/test_credhelper.ps1 - Validates that the broken credential helper
# configuration has been fixed.
#
# The break sets credsStore in %USERPROFILE%\.docker\config.json to a helper
# name with no matching docker-credential-<name>.exe on PATH, which makes the
# CLI fail to resolve credentials for a registry lookup - even for anonymous
# pulls, since the CLI always queries the credential store before making any
# request.
#
# Scoring:
#   Full marks - docker pull works AND credsStore resolves to a helper binary
#                that actually exists on PATH (or is unset, which is also
#                valid - Docker then stores auth directly in config.json).
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

$configFile = "$env:USERPROFILE\.docker\config.json"

Write-Host "=========================================="
Write-Host "Credential Helper Failure Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    # Primary functional test: this is the operation the break actually broke.
    Run-Test "docker pull succeeds (credential helper resolves)" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Stability: confirm it is not a one-off success
    Run-Test "docker pull succeeds a second time" {
        docker pull alpine:latest 2>&1 | Out-Null
    }

    # Root cause check: the configured credsStore must point at a helper binary
    # that actually exists, rather than trainees getting lucky because the image
    # happened to already be cached locally.
    #
    # Log-Test / Log-Pass / Log-Fail are used directly instead of Run-Test
    # because this check branches on a value (the credsStore string) rather
    # than a single command's exit code.
    Log-Test "credsStore resolves to an existing credential helper binary"

    $credsStore = ""
    if (Test-Path $configFile) {
        try {
            $data = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($data.PSObject.Properties.Name -contains "credsStore") {
                $credsStore = $data.credsStore
            }
        } catch {
            # A config.json that will not parse is itself a failure worth
            # reporting distinctly - the CLI cannot read it either.
            Log-Fail "config.json exists but could not be parsed as JSON: $($_.Exception.Message)"
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($credsStore)) {
        Log-Pass "credsStore resolves to an existing credential helper binary (none configured, using default auth storage)"
    } elseif (Get-Command "docker-credential-$credsStore" -ErrorAction SilentlyContinue) {
        Log-Pass "credsStore resolves to an existing credential helper binary (docker-credential-$credsStore)"
    } else {
        Log-Fail "credsStore is set to '$credsStore' but docker-credential-$credsStore was not found on PATH"
    }
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "Credential_Helper_Scenario"

$score = Calculate-Score

# Only Score: is written here. Tests Passed: and Tests Failed: are written
# by Generate-Report above.
Write-Host ""
Write-Host "Score: $score%"
