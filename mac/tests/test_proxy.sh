#!/bin/bash
# test_proxy.sh - Test proxy configuration scenario
#
# On Mac, Docker Desktop owns proxy config via settings-store.json, not
# daemon.json. Tests check the settings store for the bogus proxy address
# and verify functional restoration via docker pull and container internet
# access.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

echo "=========================================="
echo "Proxy Configuration Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon running after fix" \
        "docker info > /dev/null"

    run_test "Can pull images from Docker Hub" \
        "docker pull alpine:latest > /dev/null 2>&1"

    run_test "Containers can reach the internet" \
        "docker run --rm alpine:latest wget -q -O- http://example.com > /dev/null"

    # Check that the settings store no longer has the bogus proxy address.
    # This is the authoritative proxy config on Mac Docker Desktop.
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

    # Check that the shell RC file no longer contains the lab-injected proxy
    # block. Checking the current environment is not reliable here because
    # the test runs in a subshell that inherited its environment before any
    # RC changes took effect. Grepping the file directly tests whether the
    # trainee actually removed the injected block.
    log_test "Shell RC file proxy injection has been removed"
    local rc_file=""
    for f in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
        [ -f "$f" ] && rc_file="$f" && break
    done
    if [ -z "$rc_file" ]; then
        log_pass "No shell RC file found (nothing to check)"
    elif grep -q "DOCKER TRAINING LAB PROXY BREAK" "$rc_file"; then
        log_fail "Shell RC file still contains the lab proxy injection ($rc_file)"
    else
        log_pass "Shell RC file has no lab proxy injection"
    fi

    # Stability check
    run_test "Multiple image pulls succeed" \
        "docker pull hello-world > /dev/null 2>&1 && docker pull busybox > /dev/null 2>&1"

    # printf interprets \n correctly; single-quoted echo does not
    run_test "Build works (implies registry access)" \
        "printf 'FROM alpine:latest\nRUN echo test\n' | docker build -t test-proxy-fix - > /dev/null 2>&1"

    # Cleanup
    docker rmi test-proxy-fix hello-world busybox 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "Proxy_Configuration_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
