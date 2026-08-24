#!/bin/bash
# test_disk.sh - Tests that the disk space exhaustion scenario has been
# resolved.
#
# The break fills the Docker Desktop VM's shared virtual disk via a large
# file inside a dedicated volume. Since every docker operation shares that
# one disk, the fix is just freeing the space back up - no restart needed.
#
# Scoring:
#   Full marks - a write of meaningful size succeeds again, docker pull
#                works, and the offending container/volume are both gone.
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Disk Space Exhaustion Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"

    # Primary functional test: a write of meaningful size must succeed
    # again. A tiny write can succeed even with only a few KB free, so this
    # uses 100MB - large enough to only fit once real space has been
    # reclaimed, not just trimmed.
    docker volume rm -f test-disk-space-volume > /dev/null 2>&1 || true
    docker volume create test-disk-space-volume > /dev/null
    run_test "Can write a 100MB file (disk space reclaimed)" \
        "docker run --rm -v test-disk-space-volume:/data alpine:latest dd if=/dev/zero of=/data/proof bs=1M count=100 > /dev/null 2>&1"
    docker volume rm -f test-disk-space-volume > /dev/null 2>&1 || true

    run_test "docker pull succeeds" \
        "docker pull hello-world > /dev/null"

    # Root cause check: the offending container and volume must actually be
    # removed, not just have their content trimmed.
    log_test "disk-hog container removed"
    if ! docker ps -a --filter "name=disk-hog" --format "{{.Names}}" | grep -q "^disk-hog$"; then
        log_pass "disk-hog container removed"
    else
        log_fail "disk-hog container still exists"
    fi

    log_test "disk-hog-volume removed"
    if ! docker volume ls --filter "name=disk-hog-volume" --format "{{.Name}}" | grep -q "^disk-hog-volume$"; then
        log_pass "disk-hog-volume removed"
    else
        log_fail "disk-hog-volume still exists"
    fi
}

main() {
    test_fixed_state
    echo ""
    generate_report "Disk_Space_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
