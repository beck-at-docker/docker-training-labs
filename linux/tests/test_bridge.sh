#!/bin/bash
# tests/test_bridge.sh - Validates that the bridge network corruption scenario
# has been resolved.
#
# The break inserts a DROP rule at the top of the iptables FORWARD chain for
# all traffic from docker0. Containers start and get IPs normally (the control
# plane is untouched) but data-plane forwarding is blocked, so containers
# cannot reach each other or the internet.
#
# The iptables rules live inside the Docker Desktop VM, not on the Linux host.
# The nsenter privileged container is required to inspect and remove them.
#
# A complete fix requires removing the DROP rule from the FORWARD chain.
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "Bridge Network Corruption Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    run_test "Container can reach internet (IP)" \
        "docker run --rm alpine:latest ping -c 3 8.8.8.8 > /dev/null"

    run_test "Container can reach internet (hostname)" \
        "docker run --rm alpine:latest ping -c 3 google.com > /dev/null"

    # Test container-to-container communication by starting a target container,
    # fetching its assigned IP, and pinging it from a separate container.
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

    # Verify iptables FORWARD chain has no DROP rule for docker0.
    # nsenter is required because iptables rules live inside the Docker Desktop
    # VM, not on the Linux host.
    local forward_rules
    forward_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i iptables -L FORWARD -n)

    log_test "Docker iptables chains present"
    if echo "$forward_rules" | grep -q "DOCKER"; then
        log_pass "Docker iptables chains present"
    else
        log_fail "Docker iptables chains may be missing"
    fi

    log_test "No blocking DROP rule for docker0 in FORWARD chain"
    if ! echo "$forward_rules" | grep -q "DROP.*docker0"; then
        log_pass "No blocking DROP rule found for docker0"
    else
        log_fail "DROP rule for docker0 still present in FORWARD chain"
    fi

    # Clean up the test containers left behind by the break script
    docker rm -f broken-web broken-app 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "Bridge_Network_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
