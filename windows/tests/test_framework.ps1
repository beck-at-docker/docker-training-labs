# test_framework.ps1 - Core testing framework

$script:TESTS_RUN    = 0
$script:TESTS_PASSED = 0
$script:TESTS_FAILED = 0

function Log-Test { param($msg) Write-Host "[TEST] $msg" -ForegroundColor Cyan;  $script:TESTS_RUN++ }
function Log-Pass { param($msg) Write-Host "[PASS] $msg" -ForegroundColor Green; $script:TESTS_PASSED++ }
function Log-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red;   $script:TESTS_FAILED++ }
function Log-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

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

function Calculate-Score {
    if ($script:TESTS_RUN -eq 0) { return 0 }
    return [int]($script:TESTS_PASSED * 100 / $script:TESTS_RUN)
}
