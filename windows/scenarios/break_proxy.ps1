# break_proxy.ps1 - Corrupts proxy settings on Windows Docker Desktop
#
# On Windows, Docker Desktop ignores daemon.json proxy settings and manages
# proxy config through its own settings store at:
#   $env:APPDATA\Docker\settings-store.json
#
# This script targets that file directly and also injects bogus proxy
# environment variables into the User-scope registry (HKCU:\Environment)
# to simulate layered misconfiguration.
#
# Two mechanisms:
#   1. settings-store.json: switches proxy mode to "manual" and sets a
#      non-routable address (192.0.2.1, RFC 5737 TEST-NET). Docker Desktop
#      must be restarted to read the change, which this script handles.
#
#   2. User-scope env vars: HTTP_PROXY and HTTPS_PROXY written to
#      HKCU:\Environment via [System.Environment]::SetEnvironmentVariable,
#      so they persist across new terminals.
#
# The settings store is backed up before modification.

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
# Method 1: Corrupt the Docker Desktop settings store
#
# Read the existing JSON, merge in the broken proxy keys, and write it
# back. Merging (rather than replacing) preserves all other settings so
# Docker Desktop starts cleanly after the restart.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-proxy-${timestamp}"
Copy-Item $settingsStore $backupPath

$data = Get-Content $settingsStore -Raw | ConvertFrom-Json

$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "manual"      -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTP               -Value $bogusProxy   -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPS              -Value $bogusProxy   -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyExclude            -Value ""            -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "manual"      -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTP     -Value $bogusProxy   -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPS    -Value $bogusProxy   -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyExclude  -Value ""            -Force

$data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8

Write-Host "  Settings store updated"

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
# Restart Docker Desktop so it reads the new settings-store.json.
# Stop the process, wait for it to exit, relaunch, then poll docker info
# until the daemon is back up (max 60 seconds).
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply proxy settings..."

# Stop Docker Desktop
$dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
if ($dockerProcess) {
    $dockerProcess | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# Wait for it to fully exit
$waited = 0
while ((Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) -and $waited -lt 15) {
    Start-Sleep -Seconds 1
    $waited++
}

# Relaunch
$dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
if (Test-Path $dockerExe) {
    Start-Process $dockerExe
} else {
    Write-Host "  Warning: Could not find Docker Desktop.exe - please start it manually"
}

# Poll until daemon is ready
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
    Write-Host "  You may need to wait a moment before the break is fully active"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptoms: Image pulls fail, container internet access fails"
