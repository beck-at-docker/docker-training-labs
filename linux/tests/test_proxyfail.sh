#!/bin/bash
# tests/test_proxyfail.sh - Validates that the loopback proxy misconfiguration
# has been resolved.
#
# The break writes a manual proxy pointing to 127.0.0.1:9753 into either
# ~/.docker/desktop/settings.json (preferred) or ~/.docker/daemon.json
# (fallback if settings.json is absent). Unlike the PROXY lab which uses a
# non-routable RFC 5737 address (192.0.2.1) that silently drops packets, this
# break uses a loopback address that produces immediate "connection refused"
# errors - the key diagnostic distinction this lab teaches.
#
# A complete fix requires removing the loopback proxy from whichever config
# file the break modified, then restarting Docker Desktop.
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"

# The specific loopback address written by break_proxyfail.sh
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

    # Config check: verify neither config file still references the loopback
    # proxy. The break script writes to settings.json if it exists, falling
    # back to daemon.json. A thorough fix cleans whichever file was modified.
    log_test "settings.json does not contain the broken loopback proxy"
    if [ -f "$DESKTOP_SETTINGS" ]; then
        if python3 -c "
import json, sys
data = json.load(open('$DESKTOP_SETTINGS'))
broken = '$BROKEN_PROXY'
fields = ['ProxyHTTP', 'ProxyHTTPS', 'ContainersProxyHTTP', 'ContainersProxyHTTPS']
bad = [f for f in fields if broken in str(data.get(f, ''))]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
            log_pass "settings.json has no loopback proxy address"
        else
            log_fail "settings.json still contains the broken proxy (127.0.0.1:9753)"
        fi
    else
        log_pass "settings.json not present (not applicable)"
    fi

    log_test "daemon.json does not contain the broken loopback proxy"
    if [ -f "$DAEMON_CONFIG" ]; then
        if grep -q "127\.0\.0\.1:9753" "$DAEMON_CONFIG" 2>/dev/null; then
            log_fail "daemon.json still contains the broken proxy (127.0.0.1:9753)"
        else
            log_pass "daemon.json has no loopback proxy address"
        fi
    else
        log_pass "daemon.json not present (not applicable)"
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
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
