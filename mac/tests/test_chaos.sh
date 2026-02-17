#!/bin/bash
# test_chaos.sh - Test CHAOS MODE (all scenarios combined)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "💀 CHAOS MODE Scenario Test 💀"
echo "=========================================="
echo ""
echo "Testing all systems simultaneously..."
echo ""

test_fixed_state() {
    log_info "Running comprehensive system tests"
    
    # Test 1: DNS Resolution
    run_test "Container DNS resolution works" \
        "docker run --rm alpine:latest nslookup google.com > /dev/null"
    
    run_test "Container can ping external hostname" \
        "docker run --rm alpine:latest ping -c 3 google.com > /dev/null"
    
    # Test 2: Port Availability (test each port individually)
    for port in 80 443 3306 5432 8080; do
        run_test "Port $port is available" \
            "docker run -d --name chaos-test-$port -p $port:80 nginx:alpine > /dev/null 2>&1 && docker rm -f chaos-test-$port > /dev/null 2>&1"
    done
    
    # Test 3: Bridge Network Connectivity
    run_test "Bridge network internet connectivity (IP)" \
        "docker run --rm alpine:latest ping -c 3 8.8.8.8 > /dev/null"
    
    run_test "Bridge network DNS resolution" \
        "docker run --rm alpine:latest ping -c 3 google.com > /dev/null"
    
    # Test 4: Container-to-container communication
    docker run -d --name chaos-web nginx:alpine > /dev/null 2>&1
    sleep 2
    local web_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' chaos-web 2>/dev/null)
    
    if [ -n "$web_ip" ]; then
        run_test "Container-to-container communication" \
            "docker run --rm alpine:latest ping -c 2 $web_ip > /dev/null"
    else
        log_test "Container-to-container communication"
        log_fail "Could not get container IP (networking broken)"
    fi
    docker rm -f chaos-web > /dev/null 2>&1
    
    # Test 5: Proxy/Registry Access
    run_test "Registry access working (image pull)" \
        "docker pull busybox:latest > /dev/null 2>&1"
    docker rmi busybox:latest > /dev/null 2>&1
    
    # Test 6: Verify squatter containers removed
    local squatters=$(docker ps -a --filter "name=port-squatter" --filter "name=.hidden" --filter "name=broken-" --format "{{.Names}}" 2>/dev/null)
    log_test "All squatter containers removed"
    if [ -z "$squatters" ]; then
        log_pass "All squatter containers removed"
    else
        log_fail "Still found leftover containers: $squatters"
    fi
    
    # Test 7: Verify Python HTTP server cleanup
    log_test "Background processes cleaned up"
    if ! ps aux | grep -v grep | grep "http.server 8080" > /dev/null; then
        log_pass "Background processes cleaned up"
    else
        log_fail "Python HTTP server still running"
    fi
    
    # Test 8: Verify network subnet conflicts resolved
    local bridge_subnet=$(docker network inspect bridge 2>/dev/null | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
    local conflict_nets=$(docker network ls --format '{{.Name}}' | while read net; do
        if [ "$net" != "bridge" ] && [ "$net" != "host" ] && [ "$net" != "none" ]; then
            local subnet=$(docker network inspect "$net" 2>/dev/null | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ "$subnet" = "$bridge_subnet" ]; then
                echo "$net"
            fi
        fi
    done)
    
    log_test "No network subnet conflicts"
    if [ -z "$conflict_nets" ]; then
        log_pass "No network subnet conflicts"
    else
        log_fail "Network conflicts remain: $conflict_nets"
    fi
    
    # Test 9: System stability across multiple operations
    run_test "System stable (multiple DNS operations)" \
        "for i in 1 2 3; do docker run --rm alpine:latest nslookup google.com > /dev/null || exit 1; done"
}

# Main
main() {
    echo "This test validates that ALL four systems are fixed:"
    echo "  1. DNS Resolution"
    echo "  2. Port Bindings"
    echo "  3. Bridge Network"
    echo "  4. Proxy Configuration"
    echo ""
    
    test_fixed_state
    echo ""
    generate_report "CHAOS_MODE_Scenario"

    score=$(calculate_score)
    echo ""
    echo "Score: $score%"
    echo ""

    if [ $score -ge 95 ]; then
        echo "Grade: A+ - LEGENDARY! You conquered CHAOS MODE! 💀🏆"
        echo "You've demonstrated master-level Docker Desktop troubleshooting."
    elif [ $score -ge 90 ]; then
        echo "Grade: A - Excellent work!"
        echo "You successfully diagnosed and fixed multiple simultaneous failures."
    elif [ $score -ge 80 ]; then
        echo "Grade: B - Good job!"
        echo "Most systems fixed. Review failed tests for improvement."
    elif [ $score -ge 70 ]; then
        echo "Grade: C - Passing"
        echo "Basic fixes applied but some issues remain."
    else
        echo "Grade: F - Needs improvement"
        echo "CHAOS MODE requires fixing ALL systems. Keep practicing!"
    fi
    
    echo ""
    echo "Chaos Mode is the ultimate test. Each individual lab builds"
    echo "skills needed for this comprehensive disaster recovery scenario."
}

main "$@"
