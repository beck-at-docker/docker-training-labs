#!/bin/bash
# tests/test_sso.sh - Validates that the SSO proxy break scenario has been resolved.
#
# The break writes an asymmetric proxy config to Docker Desktop's settings
# (~/.docker/desktop/settings.json or daemon.json fallback): registry hosts
# are excluded so pulls work, but auth/identity endpoints are not excluded so
# SSO completion fails. The trainee is also signed out via docker logout.
#
# A complete fix requires:
#   1. Removing the bogus proxy or correcting the exclude list to include auth
#      endpoints, then restarting Docker Desktop
#   2. Successfully signing back in to Docker Hub
#
# IMPORTANT: The trainee must sign back in to Docker Desktop BEFORE running
# --check. This test verifies both the config fix and the functional auth state.
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

DESKTOP_SETTINGS="$HOME/.docker/desktop/settings.json"
DAEMON_CONFIG="$HOME/.docker/daemon.json"

echo "=========================================="
echo "SSO / Login Loop Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Pull success is not sufficient to confirm the fix - it worked even when
    # broken. We check it anyway to confirm the fix didn't introduce new issues.
    run_test "Image pulls still work after fix" \
        "docker pull alpine:latest > /dev/null 2>&1"

    # Authentication check: docker system info shows the logged-in username
    # when Docker Desktop has valid credentials. Empty means still signed out.
    log_test "Docker Hub user is authenticated"
    local username
    username=$(docker system info 2>/dev/null | grep -i "^Username:" | awk '{print $2}')
    if [ -n "$username" ]; then
        log_pass "Signed in as: $username"
    else
        log_fail "Not signed in to Docker Hub - fix the proxy then sign in and re-run --check"
    fi

    # Config check: verify neither settings file contains the bogus proxy.
    # Check whichever file was modified by the break script.
    log_test "Proxy configuration is valid (no bogus proxy address)"
    local config_clean=1

    if [ -f "$DESKTOP_SETTINGS" ]; then
        if python3 -c "
import json, sys
data = json.load(open('$DESKTOP_SETTINGS'))
bogus = '192.0.2'
fields = ['OverrideProxyHTTP', 'OverrideProxyHTTPS', 'ContainersOverrideProxyHTTP', 'ContainersOverrideProxyHTTPS']
bad = [f for f in fields if bogus in str(data.get(f, ''))]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
            log_pass "settings.json has no invalid proxy addresses"
        else
            log_fail "settings.json still contains the bogus proxy (192.0.2.x)"
            config_clean=0
        fi
    fi

    if [ -f "$DAEMON_CONFIG" ]; then
        if grep -q "192\.0\.2" "$DAEMON_CONFIG" 2>/dev/null; then
            log_fail "daemon.json still contains the bogus proxy (192.0.2.x)"
            config_clean=0
        else
            log_pass "daemon.json has no invalid proxy addresses"
        fi
    fi

    if [ "$config_clean" -eq 1 ] && [ ! -f "$DESKTOP_SETTINGS" ] && [ ! -f "$DAEMON_CONFIG" ]; then
        log_pass "No proxy config files found (clean state)"
    fi

    # ProxyExclude check: if a manual proxy is still configured (legitimate
    # corporate proxy), verify auth endpoints are not missing from the exclude
    # list. This catches a partial fix where registry hosts were added to
    # ProxyExclude but auth endpoints remain blocked.
    log_test "Auth endpoints are not blocked by proxy exclude list"
    if [ -f "$DESKTOP_SETTINGS" ]; then
        python3 - "$DESKTOP_SETTINGS" << 'PYEOF'
import json, sys

data = json.load(open(sys.argv[1]))
mode = data.get('ProxyHTTPMode', 'system')

if mode != 'manual':
    sys.exit(0)

proxy_addr = data.get('OverrideProxyHTTP', '')
exclude = data.get('ProxyExclude', '')
bogus_in_proxy = '192.0.2' in proxy_addr
auth_hosts = ['hub.docker.com', 'login.docker.com', 'id.docker.com']
auth_excluded = any(h in exclude for h in auth_hosts)

if bogus_in_proxy and not auth_excluded:
    print("Bogus proxy active and auth endpoints not excluded", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
        if [ $? -eq 0 ]; then
            log_pass "Auth endpoints are reachable (not blocked by proxy)"
        else
            log_fail "Auth endpoints are still blocked by the asymmetric proxy exclude list"
        fi
    else
        log_pass "Desktop settings not present (not applicable)"
    fi

    run_test "Second image pull succeeds" \
        "docker pull hello-world > /dev/null 2>&1"

    docker rmi hello-world 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "SSO_Login_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
