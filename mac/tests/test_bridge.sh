#!/bin/bash
# test_bridge.sh - Test bridge network corruption scenario

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Bridge Network Corruption Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"
    
    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"
    
    run_test "Container can reach internet (IP)" \
        "docker run --rm alpine:latest ping -c 3 8.8.8.8 > /dev/null"
    
    run_test "Container can reach internet (hostname)" \
        "docker run --rm alpine:latest ping -c 3 google.com > /dev/null"
    
    # Test container-to-container communication
    docker run -d --name test-web-fixed nginx:alpine > /dev/null 2>&1
    sleep 2
    local web_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test-web-fixed)
    
    run_test "Container-to-container communication restored" \
        "docker run --rm alpine:latest ping -c 2 $web_ip > /dev/null"
    
    docker rm -f test-web-fixed > /dev/null 2>&1
    
    # Verify no subnet conflicts remain
    local bridge_subnet=$(docker network inspect bridge | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
    local conflict_nets=$(docker network ls --format '{{.Name}}' | while read net; do
        if [ "$net" != "bridge" ] && [ "$net" != "host" ] && [ "$net" != "none" ]; then
            local subnet=$(docker network inspect $net 2>/dev/null | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ "$subnet" = "$bridge_subnet" ]; then
                echo "$net"
            fi
        fi
    done)
    
    log_test "All subnet conflicts resolved"
    if [ -z "$conflict_nets" ]; then
        log_pass "All subnet conflicts resolved"
    else
        log_fail "Still have conflicting networks: $conflict_nets"
    fi
    
    # Verify iptables FORWARD rules are correct
    local forward_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i iptables -L FORWARD -n)
    
    log_test "Docker iptables chains present"
    if echo "$forward_rules" | grep -q "DOCKER"; then
        log_pass "Docker iptables chains present"
    else
        log_fail "Docker iptables chains may be missing"
    fi
    
    log_test "No blocking DROP rules found"
    if ! echo "$forward_rules" | grep -q "DROP.*docker0"; then
        log_pass "No blocking DROP rules found"
    else
        log_fail "Still found blocking DROP rule"
    fi
    
    # Cleanup test containers
    docker rm -f broken-web broken-app 2>/dev/null || true
}

# Main
main() {
    test_fixed_state
    echo ""
    generate_report "Bridge_Network_Scenario"

    score=$(calculate_score)
    echo ""
    echo "Score: $score%"

    if [ $score -ge 90 ]; then
        echo "Grade: A - Expert network troubleshooting!"
    elif [ $score -ge 80 ]; then
        echo "Grade: B - Strong network skills"
    elif [ $score -ge 70 ]; then
        echo "Grade: C - Passing"
    else
        echo "Grade: F - Review network fundamentals"
    fi
}

main "$@"
