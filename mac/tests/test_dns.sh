#!/bin/bash
# test_dns.sh - Tests that the DNS break scenario has been correctly resolved.
#
# Scoring:
#   Full marks  - DNS works AND the DROP rules have been explicitly removed.
#                 This is the intended fix path.
#   Partial     - DNS works but the DROP rules are absent because Docker Desktop
#                 was restarted (VM wiped). Trainee gets credit for restoring
#                 service but not for understanding the root cause.
#   Fail        - DNS does not work.
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

echo "=========================================="
echo "DNS Resolution Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Basic sanity: daemon must be up
    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Core functional test: containers must resolve hostnames
    run_test "Container DNS resolution works" \
        "docker run --rm alpine:latest nslookup google.com > /dev/null"

    run_test "Container can ping external hostname" \
        "docker run --rm alpine:latest ping -c 2 google.com > /dev/null"

    # Stability check
    run_test "Multiple DNS queries succeed consistently" \
        "for i in 1 2 3; do docker run --rm alpine:latest nslookup google.com > /dev/null || exit 1; done"

    # Root cause check: were the iptables DROP rules explicitly removed?
    # If they are gone it means the trainee removed them directly (full fix).
    # If Docker Desktop was restarted instead, the rules are also gone but we
    # cannot distinguish that here - both paths pass this test. The scoring
    # note in the lab brief explains the distinction to the trainee.
    log_test "iptables DROP rules for port 53 have been removed"
    local remaining_rules
    remaining_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c \
        'iptables -L OUTPUT -n 2>/dev/null | grep -c "dpt:53.*DROP" || true')
    if [ "${remaining_rules:-0}" -eq 0 ]; then
        log_pass "iptables DROP rules for port 53 have been removed"
    else
        log_fail "iptables DROP rules for port 53 are still present ($remaining_rules rule(s) found)"
    fi
}

main() {
    test_fixed_state
    echo ""
    generate_report "DNS_Scenario"

    score=$(calculate_score)
    echo ""
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo "Score: $score%"

    if   [ "$score" -ge 90 ]; then echo "Grade: A - Excellent work!"
    elif [ "$score" -ge 80 ]; then echo "Grade: B - Good job!"
    elif [ "$score" -ge 70 ]; then echo "Grade: C - Passing"
    else                            echo "Grade: F - Needs improvement"
    fi
}

main "$@"
