# break_sso.ps1 - Simulates an SSO authentication loop caused by proxy misconfiguration.
#
# Based on real support cases (AT&T / multiple enterprise customers) where Docker
# Desktop's SSO login flow produced an immediate sign-out loop. In each case the
# root cause was a manually configured proxy that blocked Docker's auth/identity
# endpoints while leaving registry traffic accessible via ProxyExclude.
#
# On Windows, Docker Desktop manages proxy config through its settings store at
# $env:APPDATA\Docker\settings-store.json. However, on Business/Enterprise accounts
# the backend fetches admin policy from hub.docker.com on every cold start and
# overrides settings written to that file while Docker is stopped.
#
# This script therefore applies proxy settings while Docker is running, via the
# backend named pipe API (\\.\.pipe\dockerBackendApiServer). Changes propagate
# to the live daemon immediately with no restart required.
#
# The break creates two conditions:
#
#   1. Backend pipe API: sets proxy mode to "manual" with a non-routable address
#      (192.0.2.1, RFC 5737 TEST-NET). The exclude list covers Docker registry
#      and token-service hostnames, leaving hub.docker.com, login.docker.com,
#      and id.docker.com exposed to the bogus proxy.
#
#      Result: anonymous image pulls succeed (registry + auth.docker.io bypass
#      the proxy), but SSO completion fails because Docker Desktop's backend
#      callback to hub.docker.com is blocked.
#
#   2. docker logout: removes stored Docker Hub credentials so the trainee is
#      forced to attempt sign-in and encounter the SSO loop.
#
# settings-store.json is backed up before the API call so Fix-Sso in
# lib\fix.ps1 can restore it.

$settingsStore   = "$env:APPDATA\Docker\settings-store.json"
$bogusProxy      = "http://192.0.2.1:8080"
$timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"

# Exclude Docker registry and token-service endpoints so pulls still work.
# hub.docker.com, login.docker.com, and id.docker.com are intentionally
# absent - those are the SSO completion endpoints that the break targets.
$registryExclude = "registry-1.docker.io,production.cloudflare.docker.com,index.docker.io,auth.docker.io"

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
# Fix-Sso in lib\fix.ps1 restores from this backup.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-sso-${timestamp}"
Copy-Item $settingsStore $backupPath
Write-Host "  Settings store backed up"

# ------------------------------------------------------------------
# Method 1: Apply asymmetric proxy settings via the Docker Desktop
#           backend pipe API.
#
# The API uses a nested schema under vm.proxy and vm.containersProxy
# with {value, locked} objects - different from the flat PascalCase
# keys in settings-store.json. Sending flat keys returns HTTP 500.
#
# The ProxyExclude covers registry hosts so pulls still work, but
# omits hub.docker.com, login.docker.com, and id.docker.com so the
# SSO token exchange is blocked. ContainersProxy is left at system
# so container internet access is unaffected.
#
# Changes take effect immediately; no restart required.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Applying proxy settings via Docker Desktop backend API..."

$payload = (@{
    vm = @{
        proxy = @{
            mode    = @{ value = "manual" }
            http    = @{ value = $bogusProxy }
            https   = @{ value = $bogusProxy }
            exclude = @{ value = $registryExclude }
        }
        containersProxy = @{
            mode    = @{ value = "system" }
            http    = @{ value = "" }
            https   = @{ value = "" }
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
# Method 2: Sign out of Docker Hub to force the sign-in prompt.
#
# docker logout removes the stored credential for the default registry
# via the Windows credential helper. The trainee will be prompted to
# sign in and encounter the SSO loop because hub.docker.com is blocked.
# ------------------------------------------------------------------
docker logout 2>&1 | Out-Null
Write-Host "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Wait for the break to become observable.
#
# Verify two conditions: the bogus proxy is active in docker info,
# AND image pulls still work (confirming the asymmetric exclude is
# correctly applied).
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Waiting for proxy settings to take effect..."
$breakActive = $false
for ($i = 0; $i -lt 15; $i++) {
    $info = docker info 2>&1
    if ($info -match [regex]::Escape("192.0.2")) {
        # Proxy is live - verify pulls still work through the exclude list
        docker pull alpine:latest 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $breakActive = $true
            break
        }
    }
    Start-Sleep -Seconds 2
}

if (-not $breakActive) {
    Write-Host "  Warning: could not confirm break state after 30s"
    Write-Host "  Settings were applied via the API - the break may still be active."
    Write-Host "  Verify: docker info should show 192.0.2.1, docker pull should succeed"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptom: SSO sign-in loop; image pulls still work"
