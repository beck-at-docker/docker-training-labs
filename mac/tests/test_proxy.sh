#!/bin/bash
# test_proxy.sh - Test proxy configuration scenario

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Proxy Configuration Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"
    
    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"
    
    run_test "Can pull images from Docker Hub" \
        "timeout 30 docker pull alpine:latest > /dev/null 2>&1"
    
    run_test "Containers can reach internet" \
        "timeout 10 docker run --rm alpine:latest wget -q -O- https://google.com > /dev/null"
    
    # Verify daemon.json is clean or has valid proxy
    local daemon_config="$HOME/.docker/daemon.json"
    if [ -f "$daemon_config" ]; then
        if grep -q "invalid-proxy.local\|192.0.2" "$daemon_config"; then
            log_fail "Still has invalid proxy in daemon.json"
        else
            if grep -q "proxies" "$daemon_config"; then
                log_pass "Has valid proxy configuration"
            else
                log_pass "Proxy configuration removed from daemon.json"
            fi
        fi
    else
        log_pass "daemon.json removed or never existed"
    fi
    
    # Check environment variables are clean
    if echo "$HTTP_PROXY" | grep -q "192.0.2\|invalid"; then
        log_fail "Still has invalid proxy in environment"
    elif [ -n "$HTTP_PROXY" ]; then
        log_pass "Has valid proxy in environment (if corporate network)"
    else
        log_pass "No proxy environment variables (if direct internet)"
    fi
    
    # Test multiple operations to ensure stability
    run_test "Multiple image pulls work" \
        "timeout 60 docker pull hello-world && docker pull busybox > /dev/null 2>&1"
    
    run_test "Build works (implies registry access)" \
        "echo 'FROM alpine:latest\nRUN echo test' | timeout 30 docker build -t test-proxy-fix - > /dev/null 2>&1"
    
    docker rmi test-proxy-fix 2>/dev/null
    
    # Cleanup
    docker rmi hello-world busybox 2>/dev/null
}

# Main
test_fixed_state
echo ""
generate_report "Proxy_Configuration_Scenario"

local score=$(calculate_score)
echo ""
echo "Score: $score%"

if [ $score -ge 90 ]; then
    echo "Grade: A - Master of proxy configuration!"
elif [ $score -ge 80 ]; then
    echo "Grade: B - Good proxy troubleshooting"
elif [ $score -ge 70 ]; then
    echo "Grade: C - Passing"
else
    echo "Grade: F - Review proxy concepts"
fi
