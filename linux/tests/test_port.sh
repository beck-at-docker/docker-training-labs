#!/bin/bash
# tests/test_port.sh - Validates that the port binding conflict scenario has been resolved.
#
# The break occupies five ports with a mix of Docker containers and a host
# process. A complete fix requires removing all squatter containers, killing
# the Python HTTP server, and cleaning up its PID file.
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Port Binding Conflicts Scenario Test"
echo "=========================================="
echo ""

# All five ports the break script occupies
COMMON_PORTS=(80 443 3306 5432 8080)

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"

    # Verify each port is free by binding a temporary container to it.
    # All five are tested individually so trainees can see exactly which
    # ports are still occupied if the fix was incomplete.
    for port in "${COMMON_PORTS[@]}"; do
        run_test "Port $port is available" \
            "docker run -d --name test-port-$port -p $port:80 nginx:alpine > /dev/null 2>&1 && docker rm -f test-port-$port > /dev/null"
    done

    # Verify all squatter containers have been removed
    local squatters
    squatters=$(docker ps -a \
        --filter "name=port-squatter" \
        --filter "name=background-db" \
        --format "{{.Names}}")
    log_test "All port squatter containers removed"
    if [ -z "$squatters" ]; then
        log_pass "All port squatter containers removed"
    else
        log_fail "Still found squatter containers: $squatters"
    fi

    # Verify the Python host process is gone
    log_test "Python HTTP server stopped"
    if ! ps aux | grep -v grep | grep "http.server 8080" > /dev/null; then
        log_pass "Python HTTP server stopped"
    else
        log_fail "Python HTTP server still running"
    fi

    # Verify the PID file has been cleaned up
    log_test "PID file cleaned up"
    if [ ! -f /tmp/port_squatter_8080.pid ]; then
        log_pass "PID file cleaned up"
    else
        log_fail "PID file still exists at /tmp/port_squatter_8080.pid"
    fi

    # Stability: confirm ports can be allocated and freed repeatedly
    run_test "Can rapidly allocate and free ports" \
        "for i in 1 2 3; do docker run -d --name test-\$i -p 8080:80 nginx:alpine && docker rm -f test-\$i; done > /dev/null 2>&1"
}

main() {
    test_fixed_state
    echo ""
    generate_report "Port_Conflicts_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
