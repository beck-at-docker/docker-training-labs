# break_dns.ps1 - Corrupts DNS resolution in Docker Desktop (WSL2 backend)

Write-Host "Breaking Docker Desktop networking..."

# Verify Docker Desktop is running
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running or WSL2 backend is not available"
    exit 1
}

# Verify WSL2 backend
$dockerInfo = docker info 2>&1 | Out-String
if ($dockerInfo -notmatch "WSL") {
    Write-Host "Warning: This lab targets the WSL2 backend. Your backend may differ."
    Write-Host "         Proceed with caution."
    Write-Host ""
}

Write-Host "Blocking DNS queries at network level inside WSL2 VM..."

# Use semicolons rather than a multi-line heredoc - PS5.1 argument passing
# to external commands is unreliable with newlines in strings.
$iptablesCmd = "iptables-save > /tmp/iptables.dns-backup 2>/dev/null || true; " +
               "iptables -I OUTPUT -p udp --dport 53 -j DROP; " +
               "iptables -I OUTPUT -p tcp --dport 53 -j DROP; " +
               "iptables -I FORWARD -p udp --dport 53 -j DROP; " +
               "iptables -I FORWARD -p tcp --dport 53 -j DROP; " +
               "echo 'iptables rules applied'"

$result = docker run --rm --privileged --pid=host alpine:latest `
    nsenter -t 1 -m -u -n -i sh -c $iptablesCmd 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to apply iptables rules"
    Write-Host $result
    exit 1
}

# Verify rules actually landed
$verify = docker run --rm --privileged --pid=host alpine:latest `
    nsenter -t 1 -m -u -n -i sh -c 'iptables -L OUTPUT -n' 2>&1 | Out-String
if ($verify -notmatch "DROP") {
    Write-Host "Error: iptables rules did not apply - OUTPUT chain has no DROP rules"
    exit 1
}

Write-Host ""
Write-Host "Docker networking broken - DNS resolution will fail inside containers"
Write-Host ""
Write-Host "Symptoms: Containers cannot resolve external hostnames"
Write-Host ""
Write-Host "Test it:"
Write-Host "  docker run --rm alpine:latest nslookup google.com"
Write-Host "  (should timeout or fail)"
Write-Host ""
