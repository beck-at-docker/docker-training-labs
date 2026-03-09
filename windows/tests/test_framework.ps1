# test_framework.ps1 - Core testing framework
#
# Dot-sourced by every test_<scenario>.ps1 script. Provides logging helpers,
# a test execution wrapper, a report generator, and a score calculator.
#
# Output contract
# ---------------
# Check-Lab in troubleshootwinlab.ps1 parses the stdout of each test script
# for three specific lines. Generate-Report writes "Tests Passed:" and
# "Tests Failed:"; each test script writes "Score:" after calling
# Calculate-Score.
#
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>
#
# These lines must appear verbatim - any change to their format breaks
# the parser in Check-Lab.

$script:TESTS_RUN    = 0
$script:TESTS_PASSED = 0
$script:TESTS_FAILED = 0

function Log-Test { param($msg) Write-Host "[TEST] $msg" -ForegroundColor Cyan;  $script:TESTS_RUN++ }
function Log-Pass { param($msg) Write-Host "[PASS] $msg" -ForegroundColor Green; $script:TESTS_PASSED++ }
function Log-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red;   $script:TESTS_FAILED++ }
function Log-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

# Run-Test - Execute a scriptblock and record pass/fail
#
# $TestBlock is a scriptblock rather than a string so PowerShell validates
# the syntax at parse time and the IDE can provide completion. $LASTEXITCODE
# is checked (not $?) because docker and other external commands set the exit
# code but $? reflects the last PowerShell-native command result.
#
# $ExpectFailure = $true is used to test that a broken state is genuinely
# broken (e.g. confirming docker pull fails before attempting a fix).
function Run-Test {
    param(
        [string]$TestName,
        [scriptblock]$TestBlock,
        [bool]$ExpectFailure = $false
    )

    Log-Test $TestName
    try {
        $output = & $TestBlock 2>&1
        $success = $LASTEXITCODE -eq 0
    } catch {
        $success = $false
        $output = $_.Exception.Message
    }

    if ($ExpectFailure) {
        if (-not $success) { Log-Pass "$TestName (correctly failed)" }
        else                { Log-Fail "$TestName - Expected failure but succeeded" }
    } else {
        if ($success) { Log-Pass $TestName }
        else {
            Log-Fail "$TestName"
            if ($output) { Write-Host "    Output: $(($output | Select-Object -First 3) -join ' ')" -ForegroundColor DarkGray }
        }
    }
}

# Generate-Report - Print a summary and save a copy to $env:TEMP
#
# Tee-Object writes the report lines to both the pipeline (stdout, captured
# by Check-Lab's child process invocation) and to a timestamped file in
# $env:TEMP for later reference.
#
# The "Tests Passed:" and "Tests Failed:" lines here form part of the
# output contract parsed by Check-Lab. Do not change their format.
function Generate-Report {
    param([string]$Scenario)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportFile = "$env:TEMP\docker_training_${Scenario}_${timestamp}.txt"

    $lines = @(
        "==========================================",
        "Docker Training Lab Test Report",
        "Scenario: $Scenario",
        "Timestamp: $(Get-Date)",
        "==========================================",
        "",
        "Tests Run:    $script:TESTS_RUN",
        # These two lines are parsed by Check-Lab in troubleshootwinlab.ps1.
        # Format must stay exactly: "Tests Passed: <n>" and "Tests Failed: <n>"
        "Tests Passed: $script:TESTS_PASSED",
        "Tests Failed: $script:TESTS_FAILED",
        ""
    )
    if ($script:TESTS_FAILED -eq 0) { $lines += "Result: ALL TESTS PASSED" }
    else                             { $lines += "Result: SOME TESTS FAILED" }
    $lines += "=========================================="

    $lines | Tee-Object -FilePath $reportFile | Write-Host
    Write-Host ""
    Write-Host "Report saved to: $reportFile"
    return $reportFile
}

# Calculate-Score - Return integer percentage of tests passed (0-100)
function Calculate-Score {
    if ($script:TESTS_RUN -eq 0) { return 0 }
    return [int]($script:TESTS_PASSED * 100 / $script:TESTS_RUN)
}
