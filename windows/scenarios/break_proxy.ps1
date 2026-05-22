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
# Verify the proxy is reflected in the daemon by polling docker info.
#
# The API applies settings to the live httpproxy process immediately;
# docker info typically reflects the change within a single iteration.
#
# A docker pull check is deliberately NOT used here. With the proxy
# active and pointed at the silent-drop RFC 5737 address (192.0.2.1),
# a pull blocks for the full TCP SYN timeout per attempt, turning the
# polling loop into a multi-minute hang. The trainee will run docker
# pull themselves to observe the symptom; the break script must not.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Verifying proxy settings took effect..."
$proxyActive = $false
for ($i = 0; $i -lt 8; $i++) {
    $info = docker info 2>&1
    if ($info -match [regex]::Escape("192.0.2")) {
        $proxyActive = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $proxyActive) {
    Write-Host "  Warning: proxy not visible in docker info after ~16s"
    Write-Host "  The POST returned success - the break may still be active."
    Write-Host "  Verify with: docker info | Select-String -Pattern 'proxy'"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptoms: Image pulls fail, container internet access fails"
