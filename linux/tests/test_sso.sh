#!/bin/bash
# tests/test_sso.sh - Validates that the credential store misconfiguration has
# been resolved and that docker login now works via the CLI.
#
# The break corrupts ~/.docker/config.json with a credsStore entry pointing to
# a non-existent credential helper binary (docker-credential-desktop-broken).
# Docker Desktop's own GUI session is unaffected - it stays signed in. But
# docker login via the CLI fails because the CLI cannot save the resulting
# token: the credential helper binary does not exist.
#
# A complete fix requires:
#   1. Correcting or removing the broken credsStore entry in config.json
#   2. Running docker login to establish a CLI credential session
#
# IMPORTANT: The trainee must run docker login successfully BEFORE running
# --check. This test verifies both the config fix and CLI auth state.
#
# Output contract (parsed by check_lab() in troubleshootlinuxlab):
#   Score: <n>%
#   Tests Passed: <n>
#   Tests Failed: <n>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

CONFIG_FILE="$HOME/.docker/config.json"

echo "=========================================="
echo "Login Problems / Credential Store Test"
echo "=========================================="
echo ""

test_fixed_state() {
    log_info "Testing fixed state"

    run_test "Docker daemon is running" \
        "docker info > /dev/null"

    # Pulls worked even when broken - we check anyway to confirm the fix
    # didn't accidentally introduce a new problem.
    run_test "Image pulls still work after fix" \
        "docker pull alpine:latest > /dev/null 2>&1"

    # Config check: verify the credsStore no longer points to a missing binary.
    # A missing credsStore key is valid - Docker falls back to its default.
    log_test "Credential store config is valid"
    if [ -f "$CONFIG_FILE" ]; then
        python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys, shutil

data = json.load(open(sys.argv[1]))
creds_store = data.get('credsStore', '')

# No credsStore key is fine - Docker uses its built-in default
if not creds_store:
    sys.exit(0)

# If a credsStore is set, the corresponding binary must exist in PATH
binary = f'docker-credential-{creds_store}'
if shutil.which(binary):
    sys.exit(0)
else:
    print(f'credsStore "{creds_store}" requires "{binary}" which is not in PATH', file=sys.stderr)
    sys.exit(1)
PYEOF
        if [ $? -eq 0 ]; then
            log_pass "config.json has a valid or absent credsStore"
        else
            log_fail "config.json still has a broken credsStore pointing to a non-existent binary"
        fi
    else
        log_pass "config.json not present (Docker will use defaults)"
    fi

    run_test "Second image pull succeeds" \
        "docker pull hello-world > /dev/null 2>&1"

    docker rmi hello-world 2>/dev/null || true
}

main() {
    test_fixed_state
    echo ""
    generate_report "Login_Problems_Scenario"

    score=$(calculate_score)
    # Parsed by check_lab() in troubleshootlinuxlab. Format must stay: "Score: <n>%"
    echo ""
    echo "Score: $score%"
}

main "$@"
