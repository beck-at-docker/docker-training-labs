#!/bin/bash
# tests/test_framework.sh - Core test harness shared by all scenario tests

TEST_RESULTS_DIR="/tmp/docker_training_tests"
mkdir -p "$TEST_RESULTS_DIR"

# Colors (defined locally so the framework is self-contained)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ------------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------------

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ------------------------------------------------------------------
# run_test - Execute a command and record pass/fail
#
# Usage:
#   run_test "Descriptive name" "shell command string"
#   run_test "Should fail test" "command" 1   # expected exit code 1
# ------------------------------------------------------------------
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"

    log_test "$test_name"

    local output
    local exit_code
    output=$(eval "$test_command" 2>&1)
    exit_code=$?

    if [ "$expected_result" -eq 0 ]; then
        if [ $exit_code -eq 0 ]; then
            log_pass "$test_name"
            return 0
        else
            log_fail "$test_name - expected success, got exit code $exit_code"
            echo "    Output: $output" | head -n 3
            return 1
        fi
    else
        if [ $exit_code -ne 0 ]; then
            log_pass "$test_name (correctly failed)"
            return 0
        else
            log_fail "$test_name - expected failure but command succeeded"
            return 1
        fi
    fi
}

# ------------------------------------------------------------------
# generate_report - Print and save a summary to /tmp
# ------------------------------------------------------------------
generate_report() {
    local scenario=$1
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$TEST_RESULTS_DIR/${scenario}_${timestamp}.txt"

    {
        echo "=========================================="
        echo "Docker Training Lab Test Report"
        echo "Scenario: $scenario"
        echo "Timestamp: $(date)"
        echo "=========================================="
        echo ""
        echo "Tests Run:    $TESTS_RUN"
        # These two lines are parsed by check_lab() in troubleshootlinuxlab.
        # Format must stay exactly: "Tests Passed: <n>" and "Tests Failed: <n>"
        echo "Tests Passed: $TESTS_PASSED"
        echo "Tests Failed: $TESTS_FAILED"
        echo ""
        if [ $TESTS_FAILED -eq 0 ]; then
            echo "Result: ALL TESTS PASSED"
        else
            echo "Result: SOME TESTS FAILED"
        fi
        echo "=========================================="
    } | tee "$report_file"

    echo ""
    echo "Report saved to: $report_file"
}

# ------------------------------------------------------------------
# calculate_score - Return integer percentage of tests passed
# ------------------------------------------------------------------
calculate_score() {
    if [ "$TESTS_RUN" -eq 0 ]; then
        echo "0"
        return
    fi
    echo $(( TESTS_PASSED * 100 / TESTS_RUN ))
}
