#!/bin/bash
# tests/test_proxy.sh - Validates that the proxy break scenario has been resolved.
#
# The break applies an unroutable proxy (192.0.2.1:8080) via the Docker Desktop
# backend socket API (which persists to settings-store.json) and appends broken
# HTTP_PROXY/HTTPS_PROXY exports to the user's shell RC file.
# The symptom is that image pulls and container internet access both fail.
#
# A complete fix requires:
#   1. Removing the invalid proxy from Docker Desktop settings (via UI, API, or
#      editing settings-store.json) and restarting Docker Desktop if needed
#   2. Removing the proxy exports from the shell RC and restarting the terminal
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

SETTINGS_STORE="$HOME/.docker/desktop/settings-store.json"

echo "=========================================="
echo "Proxy Configuration Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Primary functional tests: image pulls and container internet access
    # are the two operations most visibly broken by a proxy misconfiguration.
    run_test "Can pull images from Docker Hub" \
        "docker pull alpine:latest > /dev/null 2>&1"

    run_test "Containers can reach the internet" \
        "docker run --rm alpine:latest wget -q -O- https://google.com > /dev/null"

    # Check that settings-store.json no longer has the bogus proxy address.
    # This is the authoritative proxy config on Docker Desktop for Linux.
    log_test "settings-store.json proxy configuration is valid"
    if [ -f "$SETTINGS_STORE" ]; then
        if python3 -c "
import json, sys
data = json.load(open('$SETTINGS_STORE'))
bogus = '192.0.2'
fields = ['ProxyHTTP', 'ProxyHTTPS', 'ContainersProxyHTTP', 'ContainersProxyHTTPS']
bad = [f for f in fields if bogus in str(data.get(f, ''))]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
            log_pass "settings-store.json has no invalid proxy addresses"
        else
            log_fail "settings-store.json still contains the bogus proxy (192.0.2.x)"
        fi
    else
        log_pass "settings-store.json not present (not applicable)"
    fi

    # Verify the environment proxy variables are not set to the broken values.
    # A legitimate corporate proxy is acceptable; the training lab's specific
    # invalid addresses (192.0.2.x is TEST-NET and unroutable) are not.
    log_test "Environment proxy variables are valid"
    if echo "${HTTP_PROXY}${HTTPS_PROXY}" | grep -q "192\.0\.2\|invalid"; then
        log_fail "Invalid proxy still present in environment variables"
    elif [ -n "$HTTP_PROXY" ]; then
        log_pass "Proxy environment variables point to a valid proxy"
    else
        log_pass "No proxy environment variables set (direct internet access)"
    fi

    # Check that the shell RC file no longer contains the lab-injected proxy
    # block. Checking the current environment is not reliable here because
    # the test runs in a subshell that inherited its environment before any
    # RC changes took effect. Grepping the file directly tests whether the
    # trainee actually removed the injected block.
    log_test "Shell RC file proxy injection has been removed"
    local rc_file=""
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
        [ -f "$f" ] && rc_file="$f" && break
    done
    if [ -z "$rc_file" ]; then
        log_pass "No shell RC file found (nothing to check)"
    elif grep -q "DOCKER TRAINING LAB PROXY BREAK" "$rc_file"; then
        log_fail "Shell RC file still contains the lab proxy injection ($rc_file)"
    else
        log_pass "Shell RC file has no lab proxy injection"
    fi

    # Stability: confirm functionality is not a one-off success.
    run_test "Multiple image pulls succeed" \
        "docker pull hello-world > /dev/null 2>&1 && docker pull busybox > /dev/null 2>&1"

    # Cleanup pulled images so the environment is tidy after grading.
    docker rmi hello-world busybox 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "Proxy_Configuration_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
