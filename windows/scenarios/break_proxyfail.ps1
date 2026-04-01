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
#                                 → connection timeout after a wait
#   This lab (127.0.0.1:9753):    packets delivered, port not listening
#                                 → immediate "connection refused" error
#
# Port 9753 is chosen because it is above the privileged range (no admin
# rights required to inspect it), is not a commonly used application port,
# and is very unlikely to be occupied on a typical developer workstation.
#
# This script modifies settings-store.json only. It does not inject proxy
# environment variables; the diagnostic focus is on reading Docker Desktop's
# proxy configuration directly from the settings store.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$brokenProxy   = "http://127.0.0.1:9753"
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
# Stop Docker Desktop BEFORE modifying settings-store.json.
#
# Docker Desktop persists its in-memory configuration back to
# settings-store.json on clean shutdown. Writing the broken settings
# first and then quitting would cause the graceful shutdown to
# overwrite our changes. Stopping the process first prevents that race.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Stopping Docker Desktop before modifying settings..."

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

# ------------------------------------------------------------------
# Corrupt the settings store with a loopback proxy address.
#
# 127.0.0.1:9753 routes to the local machine's TCP stack, which responds
# immediately with "connection refused" because nothing is listening on
# that port. Both daemon-level and container-level proxy keys are written
# so both docker pull and container internet access fail consistently.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-proxyfail-${timestamp}"
Copy-Item $settingsStore $backupPath

$data = Get-Content $settingsStore -Raw | ConvertFrom-Json

$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "manual"     -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTP               -Value $brokenProxy -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyHTTPS              -Value $brokenProxy -Force
$data | Add-Member -MemberType NoteProperty -Name ProxyExclude            -Value ""           -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "manual"     -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTP     -Value $brokenProxy -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPS    -Value $brokenProxy -Force
$data | Add-Member -MemberType NoteProperty -Name ContainersProxyExclude  -Value ""           -Force

$data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8

Write-Host "  Settings store updated"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings-store.json.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply proxy settings..."

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
    Write-Host "  You may need to wait a moment before the break is fully active"
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptoms: Image pulls fail with connection refused; container internet access fails"
