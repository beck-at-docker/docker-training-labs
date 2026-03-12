#!/bin/bash
# test_proxyfail.sh - Validates that the loopback proxy misconfiguration has
# been resolved.
#
# The break writes a manual proxy pointing to 127.0.0.1:9753 into Docker
# Desktop's settings-store.json. Unlike the PROXY lab which uses a
# non-routable RFC 5737 address (192.0.2.1) that silently drops packets, this
# break uses a loopback address that produces immediate "connection refused"
# errors - the key diagnostic distinction this lab teaches.
#
# A complete fix requires removing the loopback proxy from settings-store.json
# (either deleting the manual proxy keys or switching ProxyHTTPMode back to
# "system") and restarting Docker Desktop.
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

# The specific loopback address written by the break script
BROKEN_PROXY="127.0.0.1:9753"

echo "=========================================="
echo "Proxy Connection Refused Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    run_test "Can pull images from Docker Hub" \
        "docker pull alpine:latest > /dev/null 2>&1"

    run_test "Containers can reach the internet" \
        "docker run --rm alpine:latest wget -q -O- https://google.com > /dev/null"

    # Check that settings-store.json no longer references the loopback proxy.
    # We look for the specific address written by break_proxyfail.sh across
    # all four proxy fields (daemon-level and container-level, HTTP and HTTPS).
    log_test "settings-store.json does not contain the broken loopback proxy"
    if [ -f "$SETTINGS_STORE" ]; then
        if python3 -c "
import json, sys
data = json.load(open('$SETTINGS_STORE'))
broken = '$BROKEN_PROXY'
fields = ['ProxyHTTP', 'ProxyHTTPS', 'ContainersProxyHTTP', 'ContainersProxyHTTPS']
bad = [f for f in fields if broken in str(data.get(f, ''))]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
            log_pass "settings-store.json has no loopback proxy address"
        else
            log_fail "settings-store.json still contains the broken proxy (127.0.0.1:9753)"
        fi
    else
        log_pass "settings-store.json not present (not applicable)"
    fi

    # Stability check: a second pull confirms the fix is not transient
    run_test "Second pull succeeds" \
        "docker pull hello-world > /dev/null 2>&1"

    # Cleanup
    docker rmi hello-world alpine:latest 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "ProxyFail_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
