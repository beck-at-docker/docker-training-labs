#!/bin/bash
# test_port.sh - Test port binding conflict scenario

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Port Binding Conflicts Scenario Test"
echo "=========================================="
echo ""

# Common ports to test
COMMON_PORTS=(80 443 3306 5432 8080)

test_fixed_state() {
    log_info "Testing fixed state"
    
    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"
    
    # Verify ports are available again (test each port individually).
    # Pre-clean any test containers left over from an interrupted previous run
    # to avoid false failures caused by name conflicts rather than port conflicts.
    for port in "${COMMON_PORTS[@]}"; do
        docker rm -f "test-port-$port" > /dev/null 2>&1 || true
        run_test "Port $port is available" \
            "docker run -d --name test-port-$port -p $port:80 nginx:alpine > /dev/null 2>&1 && docker rm -f test-port-$port > /dev/null"
    done
    
    # Verify squatter containers are gone. Multiple --filter name= flags on a
    # single docker ps call are AND'd, not OR'd, so they cannot match two
    # distinct container names simultaneously. Run two separate queries instead.
    local squatters
    squatters=$(
        docker ps -a --filter "name=port-squatter" --format "{{.Names}}"
        docker ps -a --filter "name=background-db"  --format "{{.Names}}"
    )
    log_test "All port squatter containers removed"
    if [ -z "$squatters" ]; then
        log_pass "All port squatter containers removed"
    else
        log_fail "Still found squatter containers: $squatters"
    fi
    
    # Verify Python process is gone
    log_test "Python HTTP server stopped"
    if ! ps aux | grep -v grep | grep "http.server 8080" > /dev/null; then
        log_pass "Python HTTP server stopped"
    else
        log_fail "Python HTTP server still running"
    fi
    
    # Verify PID file is cleaned up
    log_test "PID file cleaned up"
    if [ ! -f /tmp/port_squatter_8080.pid ]; then
        log_pass "PID file cleaned up"
    else
        log_fail "PID file still exists at /tmp/port_squatter_8080.pid"
    fi
    
    # Stability: confirm ports can be allocated and freed repeatedly.
    # Pre-clean in case containers from a previous interrupted run remain.
    docker rm -f test-1 test-2 test-3 > /dev/null 2>&1 || true
    run_test "Can rapidly allocate and free ports" \
        "for i in 1 2 3; do docker run -d --name test-\$i -p 8080:80 nginx:alpine && docker rm -f test-\$i; done > /dev/null 2>&1"
}

# Main
main() {
    test_fixed_state
    echo ""
    generate_report "Port_Conflicts_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
