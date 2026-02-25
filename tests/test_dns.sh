#!/bin/bash
# test_dns.sh - Tests that the DNS break scenario has been correctly resolved.
#
# Expected fix path: the trainee should edit ~/.docker/daemon.json to remove
# or correct the "dns" key, then restart Docker Desktop.
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

    # Basic sanity: daemon must be up
    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Core fix verification: the bad DNS entries must be gone from daemon.json.
    # A valid fix is to remove the "dns" key, delete daemon.json entirely, or
    # replace the bad IPs with working ones - all are accepted here.
    log_test "daemon.json does not contain invalid DNS servers"
    if [ ! -f "$DAEMON_JSON" ] || \
       ( ! grep -q "$BAD_DNS_1" "$DAEMON_JSON" && ! grep -q "$BAD_DNS_2" "$DAEMON_JSON" ); then
        log_pass "daemon.json does not contain invalid DNS servers"
    else
        log_fail "daemon.json still contains invalid DNS servers ($BAD_DNS_1 or $BAD_DNS_2)"
    fi

    # Functional verification: containers must be able to resolve names
    run_test "Container DNS resolution works" \
        "docker run --rm alpine:latest nslookup google.com > /dev/null"

    run_test "Container can ping external hostname" \
        "docker run --rm alpine:latest ping -c 2 google.com > /dev/null"

    # Stability: a single fluke pass is not enough
    run_test "Multiple DNS queries succeed consistently" \
        "for i in 1 2 3; do docker run --rm alpine:latest nslookup google.com > /dev/null || exit 1; done"
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
