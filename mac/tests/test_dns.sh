#!/bin/bash
# test_dns.sh - Tests that the daemon.json DNS break scenario has been resolved.
#
# The break injects invalid nameservers into ~/.docker/daemon.json and restarts
# Docker Desktop. The daemon process uses these servers directly for its own DNS
# lookups (e.g. docker pull, registry access), even though container nslookup
# appears to work via Docker's embedded resolver.
#
# A complete fix requires both:
#   1. Removing or correcting daemon.json so it no longer contains bad servers
#   2. Restarting Docker Desktop so the daemon loads the corrected config
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

DAEMON_JSON="$HOME/.docker/daemon.json"
BAD_DNS_1="192.0.2.1"
BAD_DNS_2="192.0.2.2"

echo "=========================================="
echo "DNS Resolution Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Basic sanity: daemon must be responsive
    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Config check: the bad servers must be gone from daemon.json.
    # Acceptable fixes: remove the "dns" key, delete daemon.json entirely,
    # or replace the bad IPs with working ones.
    log_test "daemon.json does not contain invalid DNS servers"
    if [ ! -f "$DAEMON_JSON" ] || \
       ( ! grep -q "$BAD_DNS_1" "$DAEMON_JSON" && \
         ! grep -q "$BAD_DNS_2" "$DAEMON_JSON" ); then
        log_pass "daemon.json does not contain invalid DNS servers"
    else
        log_fail "daemon.json still contains invalid DNS servers ($BAD_DNS_1 or $BAD_DNS_2)"
    fi

    # Functional check: the daemon itself must be able to reach the registry.
    # This is the operation the break actually broke - docker pull uses the
    # daemon's DNS, not the container embedded resolver.
    run_test "docker pull succeeds (daemon DNS is working)" \
        "docker pull hello-world > /dev/null"

    # Stability: confirm it is not a one-off success
    run_test "docker pull succeeds a second time" \
        "docker pull alpine:latest > /dev/null"
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
