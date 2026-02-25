# break_dns.ps1 - Breaks Docker daemon DNS resolution by injecting iptables
# DROP rules for port 53 into the Docker Desktop VM's OUTPUT chain via nsenter.
#
# The daemon process runs inside the VM and uses the VM's network stack for
# its own DNS lookups (e.g. registry resolution during docker pull). Dropping
# port 53 traffic on OUTPUT prevents the daemon from resolving any external
# hostnames, producing errors like:
#
#   lookup http.docker.internal on 192.168.65.x:53:
#   write udp ...: write: operation not permitted
#
# The VM is ephemeral - iptables rules do not survive a Docker Desktop restart.
# Fix path: remove the DROP rules via nsenter (full marks), or restart Docker
# Desktop as a last resort.

Write-Host "Breaking Docker Desktop DNS resolution..."

# Verify Docker Desktop is running
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

# Inject DROP rules for port 53 (UDP and TCP) into the VM's OUTPUT chain.
# Use a semicolon-delimited string - PS5.1 argument passing to external
# commands is unreliable with newlines in strings.
$iptablesCmd = "iptables -I OUTPUT -p udp --dport 53 -j DROP; " +
               "iptables -I OUTPUT -p tcp --dport 53 -j DROP"

docker run --rm --privileged --pid=host alpine:latest `
    nsenter -t 1 -m -u -n -i sh -c $iptablesCmd 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to apply iptables rules inside the VM"
    exit 1
}

Write-Host ""
Write-Host "Docker Desktop DNS resolution broken"
Write-Host "Symptom: docker pull and registry access fail with DNS errors"
