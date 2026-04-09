# break_proxyfail.ps1 - Simulates a proxy misconfiguration where Docker Desktop
# is configured to use a proxy that actively refuses connections.
#
# Based on real support cases where Docker Desktop had a manual proxy set to an
# address that was not running - specifically a localhost port with nothing
# listening on it. This produces an immediate "connection refused" error, which
# is diagnostically distinct from the silent-drop timeout that the PROXY lab
# produces using a non-routable RFC 5737 address (192.0.2.1).
#
# The difference in symptom is the teaching point:
#
#   PROXY lab (192.0.2.1:8080):   packets routed but silently dropped
#                                 -> connection timeout after a wait
#   This lab (127.0.0.1:9753):    packets delivered, port not listening
#                                 -> immediate "connection refused" error
#
# Port 9753 is chosen because it is above the privileged range (no admin
# rights required to inspect it), is not a commonly used application port,
# and is very unlikely to be occupied on a typical developer workstation.
#
# WHY THE BACKEND PIPE API IS USED (not direct settings-store.json writes):
#
# On Business/Enterprise accounts, Docker Desktop fetches admin policy from
# hub.docker.com on every cold start and overrides settings written to the
# file while Docker is stopped. Additionally, PowerShell 5.x's
# 'Set-Content -Encoding UTF8' writes a BOM (Byte Order Mark) prefix that
# Go's JSON parser cannot handle, causing Docker Desktop to fail to read the
# modified file entirely.
#
# This script therefore applies proxy settings via the backend named pipe API
# while Docker Desktop is running - the same path the Docker Desktop UI uses.
# The API propagates the change to the live httpproxy process immediately,
# no restart required.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$brokenProxy   = "http://127.0.0.1:9753"
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Breaking Docker Desktop..."

# ------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

if (-not (Test-Path $settingsStore)) {
    Write-Host "Error: Docker Desktop settings store not found at:"
    Write-Host "  $settingsStore"
    exit 1
}

# ------------------------------------------------------------------
# Backup current settings BEFORE the break is applied.
# Fix-ProxyFail in lib\fix.ps1 restores from this backup.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-proxyfail-${timestamp}"
Copy-Item $settingsStore $backupPath
Write-Host "  Settings store backed up"

# ------------------------------------------------------------------
# Apply the loopback proxy via the Docker Desktop backend pipe API.
#
# 127.0.0.1:9753 routes to the local machine's TCP stack, which responds
# immediately with "connection refused" because nothing is listening on
# that port. Both daemon-level and container-level proxy keys are set so
# both docker pull and container internet access fail consistently.
#
# The API uses a nested schema under vm.proxy and vm.containersProxy
# with {value} objects. Changes take effect immediately; no restart
# required.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Applying proxy settings via Docker Desktop backend API..."

$payload = (@{
    vm = @{
        proxy = @{
            mode    = @{ value = "manual" }
            http    = @{ value = $brokenProxy }
            https   = @{ value = $brokenProxy }
            exclude = @{ value = "" }
        }
        containersProxy = @{
            mode    = @{ value = "manual" }
            http    = @{ value = $brokenProxy }
            https   = @{ value = $brokenProxy }
            exclude = @{ value = "" }
        }
    }
} | ConvertTo-Json -Depth 10 -Compress)

try {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
        ".", "dockerBackendApiServer",
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None)
    $pipe.Connect(5000)

    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $request = "POST /app/settings HTTP/1.0`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`n`r`n$payload"
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($request)
    $pipe.Write($reqBytes, 0, $reqBytes.Length)
    $pipe.Flush()
    $pipe.WaitForPipeDrain()

    $reader   = New-Object System.IO.StreamReader($pipe)
    $response = $reader.ReadToEnd()
    $pipe.Close()

    $statusLine = ($response -split "`r`n")[0]
    if ($statusLine -match "200|204") {
        Write-Host "  API call succeeded ($($statusLine.Trim()))"
    } else {
        Write-Host "  Error: API returned unexpected response:"
        Write-Host "  $statusLine"
        exit 1
    }
} catch {
    Write-Host "  Error: Could not connect to Docker Desktop backend pipe"
    Write-Host "  $_"
    exit 1
}

# ------------------------------------------------------------------
# Wait for the loopback proxy to become observable.
#
# The API applies settings to the live httpproxy process immediately
# but there is a brief lag before docker info reflects the change.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Waiting for proxy settings to take effect..."
$proxyActive = $false
for ($i = 0; $i -lt 15; $i++) {
    $info = docker info 2>&1
    if ($info -match [regex]::Escape("127.0.0.1:9753")) {
        $proxyActive = $true
        break
    }
    $pullErr = docker pull hello-world 2>&1
    if ($pullErr -match "connection refused" -or $pullErr -match [regex]::Escape("127.0.0.1:9753")) {
        $proxyActive = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $proxyActive) {
    Write-Host "  Warning: loopback proxy not yet observable after 30s"
    Write-Host "  Settings were applied via the API - the break may still be active."
    Write-Host "  Try: docker pull hello-world (should fail immediately with connection refused)"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptoms: Image pulls fail with connection refused; container internet access fails"
