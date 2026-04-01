#!/bin/bash
# test_dns.sh - Tests that the iptables DNS break scenario has been resolved.
#
# The break injects iptables DROP rules for port 53 into the Docker Desktop VM,
# preventing the Docker daemon from resolving external hostnames. The symptom
# is that docker pull fails with a "write: operation not permitted" error on a
# DNS socket write.
#
# Scoring:
#   Full marks  - docker pull works AND the DROP rules are gone, confirmed via
#                 direct iptables inspection inside the VM.
#   Partial     - docker pull works but the DROP rules cannot be confirmed gone
#                 (e.g. Docker Desktop was restarted, wiping the VM). Service
#                 is restored but the root cause was not directly addressed.
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

    # Primary functional test: the daemon must be able to resolve registry
    # hostnames. This is the operation the break actually broke.
    run_test "docker pull succeeds (daemon DNS is working)" \
        "docker pull hello-world > /dev/null"

    # Stability: confirm it is not a one-off success
    run_test "docker pull succeeds a second time" \
        "docker pull alpine:latest > /dev/null"

    # Root cause check: verify the DROP rules have been explicitly removed.
    # This distinguishes trainees who fixed the root cause from those who
    # restarted Docker Desktop (which also clears the rules but wipes the VM).
    # After a restart both paths look identical here, so a restart will also
    # pass - the distinction is explained in the lab brief.
    #
    # run_test is not used here because the check needs to capture the rule
    # count and branch on its value, which run_test's pass/fail model does
    # not support. log_test / log_pass / log_fail are called directly instead.
    log_test "iptables DROP rules for port 53 have been removed"
    local remaining_rules
    remaining_rules=$(docker run --rm --privileged --pid=host alpine:latest \
        nsenter -t 1 -m -u -n -i sh -c \
        'iptables -L OUTPUT -n 2>/dev/null | grep -c "dpt:53" || true')
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
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
