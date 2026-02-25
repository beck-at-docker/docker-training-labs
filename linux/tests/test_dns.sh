#!/bin/bash
# tests/test_dns.sh - Validate that the DNS lab has been correctly fixed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "DNS Resolution Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Basic daemon health check first - if this fails, nothing else will pass
    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"

    # Functional DNS resolution inside a fresh container
    run_test "Container DNS resolution works" \
        "docker run --rm alpine:latest nslookup google.com > /dev/null"

    # Ping by hostname confirms both DNS and ICMP egress are restored
    run_test "Container can ping external hostname" \
        "docker run --rm alpine:latest ping -c 2 google.com > /dev/null"

    # Inspect the OUTPUT chain directly - there should be no DROP rules for port 53
    log_test "No blocking iptables rules for DNS in OUTPUT chain"
    local output_rules
    output_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c 'iptables -L OUTPUT -n' 2>&1)

    if echo "$output_rules" | grep -q "DROP"; then
        log_fail "DROP rules for port 53 still present in OUTPUT chain"
    else
        log_pass "No DROP rules blocking DNS in OUTPUT chain"
    fi

    # Inspect the FORWARD chain too - both were poisoned by break_dns.sh
    log_test "No blocking iptables rules for DNS in FORWARD chain"
    local forward_rules
    forward_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c 'iptables -L FORWARD -n' 2>&1)

    if echo "$forward_rules" | grep -q "DROP"; then
        log_fail "DROP rules for port 53 still present in FORWARD chain"
    else
        log_pass "No DROP rules blocking DNS in FORWARD chain"
    fi

    # Stability check - run five consecutive queries to confirm the fix holds
    log_test "Multiple DNS queries work (stability check)"
    local failed=0
    for i in 1 2 3 4 5; do
        if ! docker run --rm alpine:latest nslookup google.com > /dev/null 2>&1; then
            failed=1
            break
        fi
    done

    if [ "$failed" -eq 0 ]; then
        log_pass "All five consecutive DNS queries succeeded"
    else
        log_fail "One or more DNS queries failed during stability check"
    fi
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
test_fixed_state

echo ""
generate_report "DNS_Scenario"

score=$(calculate_score)
echo ""
echo "Score: $score%"

if [ "$score" -ge 90 ]; then
    echo "Grade: A - Excellent work!"
elif [ "$score" -ge 80 ]; then
    echo "Grade: B - Good job!"
elif [ "$score" -ge 70 ]; then
    echo "Grade: C - Passing"
else
    echo "Grade: F - Needs improvement"
fi

# Structured output parsed by check_lab() in troubleshootlinuxlab.
# Format must stay exactly: "Score: <n>%", "Tests Passed: <n>", "Tests Failed: <n>"
echo ""
echo "Score: $score%"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
