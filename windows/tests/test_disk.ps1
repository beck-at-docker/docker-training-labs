# tests/test_disk.ps1 - Validates that the disk space exhaustion scenario has
# been resolved.
#
# The break fills the Docker Desktop WSL2 VM's shared virtual disk via a large
# file inside a dedicated volume. Since every docker operation shares that one
# disk, the fix is just freeing the space back up - no restart, WSL shutdown,
# or vhdx compaction needed.
#
# Scoring:
#   Full marks - a write of meaningful size succeeds again, docker pull works,
#                and the offending container and volume are both gone.
#
# Output contract (parsed by Check-Lab in troubleshootwinlab.ps1):
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report
#   Tests Failed: <n>    <- written by Generate-Report

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\test_framework.ps1"

Write-Host "=========================================="
Write-Host "Disk Space Exhaustion Scenario Test"
Write-Host "=========================================="
Write-Host ""

function Test-FixedState {
    Log-Info "Testing fixed state"

    Run-Test "Docker daemon running after fix" {
        docker info 2>&1 | Out-Null
    }

    # Primary functional test: a write of meaningful size must succeed again.
    # A tiny write can succeed even with only a few KB free, so this uses
    # 100MB - large enough to only fit once real space has been reclaimed,
    # not just trimmed.
    #
    # 'throw' is used instead of 'exit' to signal failure. 'exit' inside a
    # scriptblock called with & terminates the entire PowerShell session.
    # Run-Test's try/catch converts a thrown exception into a test failure.
    docker volume rm -f test-disk-space-volume 2>&1 | Out-Null
    docker volume create test-disk-space-volume 2>&1 | Out-Null
    Run-Test "Can write a 100MB file (disk space reclaimed)" {
        docker run --rm -v test-disk-space-volume:/data alpine:latest `
            dd if=/dev/zero of=/data/proof bs=1M count=100 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "100MB write failed - disk space has not been reclaimed" }
    }
    docker volume rm -f test-disk-space-volume 2>&1 | Out-Null

    Run-Test "docker pull succeeds" {
        docker pull hello-world 2>&1 | Out-Null
    }

    # Root cause check: the offending container and volume must actually be
    # removed, not just have their contents trimmed.
    Log-Test "disk-hog container removed"
    $hogContainer = docker ps -a --filter "name=disk-hog" --format "{{.Names}}" 2>&1
    if (-not $hogContainer) {
        Log-Pass "disk-hog container removed"
    } else {
        Log-Fail "disk-hog container still exists"
    }

    Log-Test "disk-hog-volume removed"
    $hogVolume = docker volume ls --filter "name=disk-hog-volume" --format "{{.Name}}" 2>&1
    if (-not $hogVolume) {
        Log-Pass "disk-hog-volume removed"
    } else {
        Log-Fail "disk-hog-volume still exists"
    }
}

Test-FixedState

Write-Host ""
$reportFile = Generate-Report "Disk_Space_Scenario"

$score = Calculate-Score

# Only Score: is written here. Tests Passed: and Tests Failed: are written
# by Generate-Report above.
Write-Host ""
Write-Host "Score: $score%"
