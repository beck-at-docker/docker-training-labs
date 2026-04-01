#!/bin/bash
# all.sh - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Restoring ALL Docker Desktop Systems"
echo "=========================================="
echo ""
echo "This will fix:"
echo "  1. Bridge Network"
echo "  2. DNS Resolution"
echo "  3. Proxy Configuration"
echo "  4. Proxy Failure Simulation"
echo "  5. SSO Configuration"
echo "  6. Auth Config Enforcement"
echo "  7. Port Conflicts"
echo ""
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=========================================="

# Tracks which steps failed so we can report clearly at the end.
failed_steps=()

# run_fix <label> <script>
# Runs the given fix script and records pass/fail. Never exits early.
run_fix() {
    local label="$1"
    local script="$2"
    local exit_code

    echo ""
    echo "--- $label ---"
    bash "$SCRIPT_DIR/$script"
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "  -> OK"
    else
        echo "  -> FAILED (exit code $exit_code)"
        failed_steps+=("$label")
    fi
    echo ""
    echo "=========================================="
}

# Fix bridge first (iptables rules affect all container networking),
# then DNS, then proxy variants (proxy.sh triggers a Docker restart),
# then SSO and authconfig (settings-store.json changes), ports last.
run_fix "[1/7] Bridge Network"          "bridge.sh"
run_fix "[2/7] DNS Resolution"          "dns.sh"
run_fix "[3/7] Proxy Configuration"     "proxy.sh"
run_fix "[4/7] Proxy Failure Simulation" "proxyfail.sh"
run_fix "[5/7] SSO Configuration"       "sso.sh"
run_fix "[6/7] Auth Config Enforcement" "authconfig.sh"
run_fix "[7/7] Port Conflicts"          "ports.sh"

echo ""
echo "=========================================="

if [ ${#failed_steps[@]} -eq 0 ]; then
    echo "All Systems Restored"
    echo "=========================================="
    echo ""
    echo "Docker Desktop was restarted automatically during the proxy fix."
    echo "Verify everything is working:"
    echo "  docker pull hello-world"
    echo "  docker run --rm alpine:latest ping -c 2 google.com"
    echo "  docker run -p 8080:80 nginx:alpine"
    echo ""
    exit 0
else
    echo "Restore completed with errors"
    echo "=========================================="
    echo ""
    echo "The following steps failed:"
    for step in "${failed_steps[@]}"; do
        echo "  - $step"
    done
    echo ""
    echo "Review the output above for details on each failure."
    echo ""
    exit 1
fi
