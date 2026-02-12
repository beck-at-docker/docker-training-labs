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
    
    # Verify ports are available again
    for port in "${COMMON_PORTS[@]}"; do
        run_test "Port $port is available" \
            "docker run -d --name test-port-$port -p $port:80 nginx:alpine > /dev/null 2>&1 && docker rm -f test-port-$port > /dev/null"
    done
    
    # Verify squatter containers are gone
    local squatters=$(docker ps -a --filter "name=port-squatter" --filter "name=.hidden" --format "{{.Names}}")
    if [ -z "$squatters" ]; then
        log_pass "All port squatter containers removed"
    else
        log_fail "Still found squatter containers: $squatters"
    fi
    
    # Verify Python process is gone
    if ! ps aux | grep -v grep | grep "http.server 8080" > /dev/null; then
        log_pass "Python HTTP server stopped"
    else
        log_fail "Python HTTP server still running"
    fi
    
    # Verify PID file is cleaned up
    if [ ! -f /tmp/port_squatter_8080.pid ]; then
        log_pass "PID file cleaned up"
    else
        log_warn "PID file still exists"
    fi
    
    # Test rapid port allocation/deallocation
    run_test "Can rapidly allocate and free ports" \
        "for i in {1..3}; do docker run -d --name test-\$i -p 8080:80 nginx:alpine && docker rm -f test-\$i; done > /dev/null 2>&1"
}

# Main
test_fixed_state
echo ""
generate_report "Port_Conflicts_Scenario"

local score=$(calculate_score)
echo ""
echo "Score: $score%"

if [ $score -ge 90 ]; then
    echo "Grade: A - Excellent port management!"
elif [ $score -ge 80 ]; then
    echo "Grade: B - Good troubleshooting"
elif [ $score -ge 70 ]; then
    echo "Grade: C - Passing"
else
    echo "Grade: F - Review port conflict resolution"
fi
