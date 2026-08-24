#!/bin/bash
# test_credhelper.sh - Tests that the broken credential helper configuration
# has been fixed.
#
# The break sets credsStore in ~/.docker/config.json to a helper name with
# no matching docker-credential-<name> binary in $PATH, which makes the CLI
# fail to resolve credentials for a registry lookup - even for anonymous
# pulls, since the CLI always queries the credential store before making
# any request.
#
# Scoring:
#   Full marks - docker pull works AND credsStore resolves to a helper
#                binary that actually exists in $PATH (or is unset, which
#                is also valid - Docker falls back to storing auth directly
#                in config.json).
#
# Output contract (parsed by check_lab() in troubleshootmaclab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

CONFIG_FILE="$HOME/.docker/config.json"

echo "=========================================="
echo "Credential Helper Failure Scenario Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    # Primary functional test: this is the operation the break actually broke.
    run_test "docker pull succeeds (credential helper resolves)" \
        "docker pull hello-world > /dev/null"

    # Stability: confirm it is not a one-off success
    run_test "docker pull succeeds a second time" \
        "docker pull alpine:latest > /dev/null"

    # Root cause check: the configured credsStore must point at a helper
    # binary that actually exists, rather than trainees getting lucky
    # because the image happened to already be cached locally.
    #
    # log_test / log_pass / log_fail are used directly instead of run_test
    # because this check branches on a value (the credsStore string) rather
    # than a single command's exit code.
    log_test "credsStore resolves to an existing credential helper binary"
    local creds_store
    if [ -f "$CONFIG_FILE" ]; then
        creds_store=$(python3 -c "
import json
try:
    with open('$CONFIG_FILE') as f:
        print(json.load(f).get('credsStore', ''))
except Exception:
    print('')
")
    else
        creds_store=""
    fi

    if [ -z "$creds_store" ]; then
        log_pass "credsStore resolves to an existing credential helper binary (none configured, using default auth storage)"
    elif command -v "docker-credential-$creds_store" > /dev/null 2>&1; then
        log_pass "credsStore resolves to an existing credential helper binary (docker-credential-$creds_store)"
    else
        log_fail "credsStore is set to '$creds_store' but docker-credential-$creds_store was not found in \$PATH"
    fi
}

main() {
    test_fixed_state
    echo ""
    generate_report "Credential_Helper_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootmaclab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
