#!/bin/bash
# test_authconfig.sh - Validates that the allowedOrgs misconfiguration has
# been resolved.
#
# The break writes a URL-format value to the allowedOrgs key in
# settings-store.json (e.g. ["https://hub.docker.com/u/required-org"] instead
# of the correct plain-slug format ["required-org"]). Docker Desktop's org
# enforcement check matches against plain slugs only, so the URL value never
# matches and every sign-in attempt is immediately rejected.
#
# A complete fix requires:
#   1. Correcting allowedOrgs to use a plain slug (or removing the key
#      entirely) in settings-store.json and restarting Docker Desktop
#   2. Successfully signing back in to Docker Hub
#
# IMPORTANT: The trainee must sign back in to Docker Desktop BEFORE running
# --check. The test verifies both the config fix and the restored auth state.
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

SETTINGS_STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

echo "=========================================="
echo "Auth Config (allowedOrgs) Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Primary config check: allowedOrgs must not contain a URL-format value.
    # Docker Desktop expects plain org slugs (e.g. "my-company"). Any value
    # containing "https://" is definitively wrong regardless of the org name.
    # Valid fixed states: key absent, empty array, or plain-slug array.
    log_test "allowedOrgs does not contain URL-format values"
    if [ -f "$SETTINGS_STORE" ]; then
        if python3 -c "
import json, sys
data = json.load(open('$SETTINGS_STORE'))
orgs = data.get('allowedOrgs', [])
bad = [o for o in orgs if str(o).startswith('http')]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
            log_pass "allowedOrgs contains no URL-format values"
        else
            log_fail "allowedOrgs still contains a URL-format value - should be a plain org slug or empty"
        fi
    else
        log_pass "settings-store.json not present (not applicable)"
    fi

    # Authentication check: the trainee must have signed back in after fixing
    # the config. An empty username means the config is fixed but step two
    # (re-authenticating) has not been completed.
    log_test "Docker Hub user is authenticated"
    local username
    username=$(docker system info 2>/dev/null | grep -i "^Username:" | awk '{print $2}')
    if [ -n "$username" ]; then
        log_pass "Signed in as: $username"
    else
        log_fail "Not signed in to Docker Hub - fix the config, sign in, then re-run --check"
    fi

    # Functional verification: confirm registry access is healthy.
    # The break does not directly block pulls (anonymous access still works),
    # but this confirms Docker Desktop is clean after the fix.
    run_test "Can pull images from Docker Hub" \
        "docker pull hello-world > /dev/null 2>&1"

    # Cleanup
    docker rmi hello-world 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "AuthConfig_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
