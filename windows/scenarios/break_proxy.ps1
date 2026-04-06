# break_proxy.ps1 - Corrupts proxy settings on Windows Docker Desktop
#
# On Windows, Docker Desktop manages proxy config through its settings
# store at $env:APPDATA\Docker\settings-store.json. However, on
# Business/Enterprise accounts the backend fetches admin policy from
# hub.docker.com on every cold start and can override settings written
# to that file while Docker is stopped.
#
# This script therefore applies the proxy settings while Docker is
# running, via the backend named pipe API (\\.\.pipe\dockerBackendApiServer).
# This is the same code path the Docker Desktop UI uses, so the change
# propagates to the live daemon immediately with no restart required.
#
# Two mechanisms are used to simulate layered misconfiguration:
#
#   1. Backend pipe API: sets proxy mode to "manual" and points both
#      daemon-level and container-level proxy to 192.0.2.1:8080, an
#      RFC 5737 TEST-NET address that silently drops all traffic.
#      The API uses a nested schema (vm.proxy / vm.containersProxy)
#      that differs from the flat key names in settings-store.json.
#
#   2. User-scope env vars: HTTP_PROXY and HTTPS_PROXY written to
#      HKCU:\Environment via [System.Environment]::SetEnvironmentVariable,
#      so they persist across new terminals.
#
# settings-store.json is backed up before the API call so Fix-Proxy
# in lib\fix.ps1 can restore it.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$bogusProxy    = "http://192.0.2.1:8080"
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Breaking Docker Desktop..."

# Verify Docker Desktop is running
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

# Verify the settings store exists
if (-not (Test-Path $settingsStore)) {
    Write-Host "Error: Docker Desktop settings store not found at:"
    Write-Host "  $settingsStore"
    exit 1
}

# ------------------------------------------------------------------
# Backup current settings BEFORE the break is applied.
# Fix-Proxy in lib\fix.ps1 restores from this backup.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-proxy-${timestamp}"
Copy-Item $settingsStore $backupPath
Write-Host "  Settings store backed up"

# ------------------------------------------------------------------
# Method 1: Apply proxy settings via the Docker Desktop backend pipe API.
#
# The API uses a nested schema under vm.proxy and vm.containersProxy
# with {value, locked} objects - different from the flat PascalCase
# keys in settings-store.json. Sending flat keys returns HTTP 500.
#
# Changes take effect immediately in the running daemon; no restart
# is required.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Applying proxy settings via Docker Desktop backend API..."

$payload = (@{
    vm = @{
        proxy = @{
            mode    = @{ value = "manual" }
            http    = @{ value = $bogusProxy }
            https   = @{ value = $bogusProxy }
            exclude = @{ value = "" }
        }
        containersProxy = @{
            mode    = @{ value = "manual" }
            http    = @{ value = $bogusProxy }
            https   = @{ value = $bogusProxy }
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

    # Extract HTTP status code from the response line
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
# Method 2: Inject bogus proxy into User-scope environment variables.
# [System.Environment]::SetEnvironmentVariable at "User" scope writes
# to HKCU:\Environment, which persists across new terminals.
# ------------------------------------------------------------------
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY",  $bogusProxy, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $bogusProxy, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY",    "",          "User")

Write-Host "  User-scope proxy environment variables set"

# ------------------------------------------------------------------
# Wait for the proxy to become observable in the daemon.
#
# The API applies settings immediately, but there can be a brief lag
# before docker info reflects the change. Poll in two stages:
#   Stage 1 - docker info should report the bogus proxy address
#   Stage 2 - docker pull should fail with a proxy-related error
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Waiting for proxy settings to take effect..."
$proxyActive = $false
for ($i = 0; $i -lt 15; $i++) {
    # Stage 1: check docker info for the bogus address
    $info = docker info 2>&1
    if ($info -match [regex]::Escape("192.0.2")) {
        $proxyActive = $true
        break
    }

    # Stage 2: attempt a pull and look for proxy-related failure
    $pullErr = docker pull hello-world 2>&1
    if ($pullErr -match [regex]::Escape("192.0.2") -or $pullErr -match "proxyconnect") {
        $proxyActive = $true
        break
    }

    Start-Sleep -Seconds 2
}

if (-not $proxyActive) {
    Write-Host "  Warning: proxy not yet visible in docker info or pull output after 30s"
    Write-Host "  Settings were applied via the API - the break may still be active."
    Write-Host "  Try: docker pull hello-world (should time out)"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptoms: Image pulls fail, container internet access fails"
