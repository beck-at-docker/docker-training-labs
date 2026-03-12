#!/bin/bash
# test_sso.sh - Validates that the SSO proxy break scenario has been resolved.
#
# The break writes an asymmetric proxy config to Docker Desktop's settings store:
# registry hosts are excluded from the proxy (so pulls work), but Docker's auth
# and identity endpoints are not excluded (so SSO completion fails). The trainee
# is also signed out via docker logout to force the sign-in flow.
#
# A complete fix requires:
#   1. Removing the bogus proxy or correcting ProxyExclude to include auth
#      endpoints, and restarting Docker Desktop
#   2. Successfully signing back in to Docker Hub
#
# IMPORTANT: The trainee must sign back in to Docker Desktop BEFORE running
# --check. The test verifies both the config fix and the functional auth state.
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

echo "=========================================="
echo "SSO / Login Loop Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Primary functional test: image pulls must work both before and after fix.
    # Pull success is not sufficient to confirm the fix - it worked even when
    # broken. We check it anyway to confirm the fix didn't break anything new.
    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    run_test "Image pulls still work after fix" \
        "docker pull alpine:latest > /dev/null 2>&1"

    # Authentication check: the trainee must have signed back in.
    # docker system info shows the logged-in username when Docker Desktop
    # has valid credentials stored. An empty result means they are still
    # signed out and the SSO loop has not been resolved end-to-end.
    log_test "Docker Hub user is authenticated"
    local username
    username=$(docker system info 2>/dev/null | grep -i "^Username:" | awk '{print $2}')
    if [ -n "$username" ]; then
        log_pass "Signed in as: $username"
    else
        log_fail "Not signed in to Docker Hub - fix the proxy then sign in and re-run --check"
    fi

    # Proxy config check: verify settings-store.json no longer has the bogus
    # proxy address. A valid fix is either:
    #   a) ProxyHTTPMode back to "system" (proxy removed entirely)
    #   b) ProxyHTTP pointing to a real, reachable proxy
    # Either way, 192.0.2.1 must not appear in the proxy fields.
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

    # ProxyExclude check: if a manual proxy is still configured (legitimate
    # corporate proxy scenario), verify the auth endpoints are not missing from
    # the exclude list. This distinguishes a proper fix from a partial one where
    # the trainee only added registry hosts to ProxyExclude but left auth blocked.
    log_test "Auth endpoints are not blocked by proxy exclude list"
    if [ -f "$SETTINGS_STORE" ]; then
        python3 - "$SETTINGS_STORE" << 'PYEOF'
import json, sys

data = json.load(open(sys.argv[1]))
mode = data.get('ProxyHTTPMode', 'system')

if mode != 'manual':
    # Proxy is in system or off mode - no manual exclusion list to worry about
    sys.exit(0)

# Manual proxy is configured. If auth endpoints are excluded, the fix is
# complete. If none are excluded, auth traffic will flow through whatever
# proxy is configured - which may or may not be valid. We pass this check
# unless we can confirm 192.0.2.x is the proxy AND auth is not excluded.
proxy_addr = data.get('ProxyHTTP', '')
exclude = data.get('ProxyExclude', '')

bogus_in_proxy = '192.0.2' in proxy_addr
auth_hosts = ['hub.docker.com', 'login.docker.com', 'id.docker.com']
auth_excluded = any(h in exclude for h in auth_hosts)

if bogus_in_proxy and not auth_excluded:
    print("Bogus proxy active and auth endpoints not excluded", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
        local pyexit=$?
        if [ $pyexit -eq 0 ]; then
            log_pass "Auth endpoints are reachable (not blocked by proxy)"
        else
            log_fail "Auth endpoints are still blocked by the asymmetric proxy exclude list"
        fi
    else
        log_pass "settings-store.json not present (not applicable)"
    fi

    # Stability: confirm a second pull succeeds (rules out transient success)
    run_test "Second image pull succeeds" \
        "docker pull hello-world > /dev/null 2>&1"

    # Cleanup
    docker rmi hello-world 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "SSO_Login_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
