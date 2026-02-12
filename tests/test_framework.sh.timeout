#!/bin/bash
# test_framework.sh - Core testing framework

TEST_RESULTS_DIR="/tmp/docker_training_tests"
mkdir -p "$TEST_RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((TESTS_RUN++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}" # 0 for success, 1 for failure expected
    
    log_test "$test_name"
    
    local output
    local exit_code
    output=$(eval "$test_command" 2>&1)
    exit_code=$?
    
    if [ "$expected_result" -eq 0 ]; then
        # Expecting success
        if [ $exit_code -eq 0 ]; then
            log_pass "$test_name"
            return 0
        else
            log_fail "$test_name - Expected success but got exit code $exit_code"
            echo "    Output: $output" | head -n 3
            return 1
        fi
    else
        # Expecting failure
        if [ $exit_code -ne 0 ]; then
            log_pass "$test_name (correctly failed)"
            return 0
        else
            log_fail "$test_name - Expected failure but succeeded"
            return 1
        fi
    fi
}

# Generate test report
generate_report() {
    local scenario=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$TEST_RESULTS_DIR/${scenario}_${timestamp}.txt"
    
    {
        echo "=========================================="
        echo "Docker Training Lab Test Report"
        echo "Scenario: $scenario"
        echo "Timestamp: $(date)"
        echo "=========================================="
        echo ""
        echo "Tests Run:    $TESTS_RUN"
        echo "Tests Passed: $TESTS_PASSED"
        echo "Tests Failed: $TESTS_FAILED"
        echo ""
        if [ $TESTS_FAILED -eq 0 ]; then
            echo "Result: ✅ ALL TESTS PASSED"
        else
            echo "Result: ❌ SOME TESTS FAILED"
        fi
        echo "=========================================="
    } | tee "$report_file"
    
    echo ""
    echo "Report saved to: $report_file"
}

# Calculate score
calculate_score() {
    if [ $TESTS_RUN -eq 0 ]; then
        echo "0"
        return
    fi
    echo $(( TESTS_PASSED * 100 / TESTS_RUN ))
}
