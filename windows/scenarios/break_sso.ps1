# break_sso.ps1 - Simulates an SSO authentication loop caused by proxy misconfiguration.
#
# Based on real support cases (AT&T / multiple enterprise customers) where Docker
# Desktop's SSO login flow produced an immediate sign-out loop. In each case the
# root cause was a manually configured proxy that blocked Docker's auth/identity
# endpoints while leaving registry traffic accessible via ProxyExclude.
#
# On Windows, Docker Desktop stores its proxy config in:
#   $env:APPDATA\Docker\settings-store.json
#
# The break creates two conditions:
#
#   1. settings-store.json: sets proxy mode to "manual" with a non-routable
#      address (192.0.2.1, RFC 5737 TEST-NET). The ProxyExclude list covers
#      Docker registry and token-service hostnames, leaving hub.docker.com,
#      login.docker.com, and id.docker.com exposed to the bogus proxy.
#
#      Result: anonymous image pulls succeed (registry + auth.docker.io bypass
#      the proxy), but SSO completion fails because Docker Desktop's backend
#      callback to hub.docker.com is blocked.
#
#   2. docker logout: removes stored Docker Hub credentials, placing Docker
#      Desktop in a signed-out state. When the trainee attempts SSO, the browser
#      auth succeeds but the token exchange with hub.docker.com goes through the
#      bogus proxy and fails, producing an immediate sign-out loop.
#
# Docker Desktop is restarted after the settings change.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$bogusProxy    = "http://192.0.2.1:8080"
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"

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
# Method 1: Corrupt the Docker Desktop settings store with an asymmetric
#           proxy configuration.
#
# Merge proxy keys into the existing JSON to preserve all other settings.
# Add-Member -Force is used because direct property assignment on
# ConvertFrom-Json objects is unreliable in PS5.1.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-sso-${timestamp}"
Copy-Item $settingsStore $backupPath

$data = Get-Content $settingsStore -Raw | ConvertFrom-Json

$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "manual"          -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTP               -Value $bogusProxy        -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPS              -Value $bogusProxy        -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyExclude            -Value $registryExclude  -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "system"           -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTP     -Value ""                 -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPS    -Value ""                 -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyExclude  -Value ""                 -Force

$data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8

Write-Host "  Settings store updated"

# ------------------------------------------------------------------
# Method 2: Sign out of Docker Hub to force the sign-in prompt.
#
# docker logout removes the stored credential for the default registry
# via the Windows credential helper. After Docker Desktop restarts with
# the broken proxy config, the trainee will be prompted to sign in. Their
# SSO attempt will loop because hub.docker.com is blocked.
# ------------------------------------------------------------------
docker logout 2>&1 | Out-Null
Write-Host "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings-store.json.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply proxy settings..."

$dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
if ($dockerProcess) {
    $dockerProcess | Stop-Process -Force
    Start-Sleep -Seconds 2
}

$waited = 0
while ((Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) -and $waited -lt 15) {
    Start-Sleep -Seconds 1
    $waited++
}

$dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
if (Test-Path $dockerExe) {
    Start-Process $dockerExe
} else {
    Write-Host "  Warning: Could not find Docker Desktop.exe - please start it manually"
}

Write-Host "Docker Desktop must be started manually..."
Write-Host "  Waiting for Docker Desktop to restart..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Host "  Warning: Docker Desktop did not come back within 60s"
    Write-Host "  Wait a moment before attempting to sign in"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptom: SSO sign-in loop; image pulls still work"
