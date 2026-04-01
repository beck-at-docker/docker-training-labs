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
    sleep 2  # wait for the container's network interface to be assigned an IP
    local web_ip
    web_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test-web-fixed 2>/dev/null)

    log_test "Container-to-container communication restored"
    if [ -n "$web_ip" ]; then
        if docker run --rm alpine:latest ping -c 2 "$web_ip" > /dev/null 2>&1; then
            log_pass "Container-to-container communication restored"
        else
            log_fail "Container-to-container ping failed (target: $web_ip)"
        fi
    else
        log_fail "Could not get container IP - container may not have started"
    fi

    docker rm -f test-web-fixed > /dev/null 2>&1
    
    # Verify no subnet conflicts remain
    local bridge_subnet
    bridge_subnet=$(docker network inspect bridge | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
    local conflict_nets
    conflict_nets=$(docker network ls --format '{{.Name}}' | while read net; do
        if [ "$net" != "bridge" ] && [ "$net" != "host" ] && [ "$net" != "none" ]; then
            # 'local' is only valid inside a function; this runs in a subshell
            # so declare subnet as a plain variable instead.
            subnet=$(docker network inspect "$net" 2>/dev/null | grep -o '"Subnet": *"[^"]*"' | head -1 | cut -d'"' -f4)
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
    local forward_rules
    forward_rules=$(docker run --rm --privileged --pid=host alpine:latest \
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
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
