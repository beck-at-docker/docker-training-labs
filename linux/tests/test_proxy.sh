#!/bin/bash
# tests/test_proxy.sh - Validates that the proxy break scenario has been resolved.
#
# The break writes an invalid proxy into ~/.docker/daemon.json and appends
# broken HTTP_PROXY/HTTPS_PROXY exports to the user's shell RC file.
# The symptom is that image pulls and container internet access both fail.
#
# A complete fix requires:
#   1. Removing the invalid proxy from daemon.json and restarting Docker Desktop
#   2. Removing the proxy exports from the shell RC and restarting the terminal
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

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

    # Verify daemon.json is clean - no invalid proxy values left behind.
    local daemon_config="$HOME/.docker/daemon.json"
    log_test "daemon.json proxy configuration is valid"
    if [ -f "$daemon_config" ]; then
        if grep -q "invalid-proxy.local\|192\.0\.2" "$daemon_config"; then
            log_fail "Invalid proxy still present in daemon.json"
        else
            if grep -q "proxies" "$daemon_config"; then
                log_pass "daemon.json has a valid proxy configuration"
            else
                log_pass "Proxy configuration removed from daemon.json"
            fi
        fi
    else
        log_pass "daemon.json removed or never existed"
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
