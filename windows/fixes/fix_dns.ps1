# fix_dns.ps1 - Restore Docker daemon DNS resolution in Docker Desktop
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# The DNS break injects two iptables DROP rules for port 53 into the Docker
# Desktop VM's OUTPUT chain via nsenter. This script removes those rules
# using the same mechanism.

$ErrorActionPreference = "Stop"

Write-Host "Fixing Docker Desktop DNS..."

# Verify Docker Desktop is running before attempting anything
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

# Remove the DROP rules for port 53 (UDP and TCP) from the VM's OUTPUT chain.
# -D deletes the first matching rule; run once per protocol to match the two
# rules injected by break_dns.ps1.
# Use a semicolon-delimited string - PS5.1 argument passing to external
# commands is unreliable with newlines in strings.
$iptablesCmd = "iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true; " +
               "iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true"

docker run --rm --privileged --pid=host alpine:latest `
    nsenter -t 1 -m -u -n -i sh -c $iptablesCmd 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to access the Docker VM via nsenter"
    exit 1
}

# Verify the fix
Write-Host ""
Write-Host "Verifying DNS resolution..."
docker pull hello-world 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "DNS resolution working"
} else {
    Write-Host "DNS still broken - may need Docker Desktop restart"
}
