# break_credhelper.ps1 - Corrupts the credsStore in the Docker CLI config so
# the CLI cannot find its credential helper binary.
#
# Docker Desktop for Windows configures %USERPROFILE%\.docker\config.json with
# "credsStore": "desktop", which tells the CLI to shell out to
# docker-credential-desktop.exe for every registry auth lookup - including
# anonymous pulls, since the CLI always checks for stored credentials for the
# target registry host before making the request. If that binary cannot be
# found, EVERY registry operation fails immediately, before any network
# request is even made:
#
#   error getting credentials - err: exec: "docker-credential-desktop-broken":
#   executable file not found in %PATH%
#
# This is a genuinely common Docker Desktop support case on Windows (usually
# caused by a stale/corrupt config.json, a botched manual edit, or the Docker
# bin directory dropping off PATH after a reinstall or upgrade) - the daemon is
# completely healthy, but the CLI cannot even get as far as an HTTP request.
#
# No admin rights are needed: config.json lives in the user profile, and no
# Docker Desktop restart is required since the CLI re-reads it on every
# invocation.

$configFile = "$env:USERPROFILE\.docker\config.json"
$dockerDir  = "$env:USERPROFILE\.docker"

Write-Host "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

if (-not (Test-Path $dockerDir)) {
    New-Item -ItemType Directory -Force -Path $dockerDir | Out-Null
}

# Use BOM-free UTF-8 for all JSON writes. PowerShell 5.x
# 'Set-Content -Encoding UTF8' emits a BOM (EF BB BF) that Go's
# encoding/json - used by the Docker CLI - rejects outright.
if (-not (Test-Path $configFile)) {
    [System.IO.File]::WriteAllText($configFile, '{}', [System.Text.UTF8Encoding]::new($false))
}

# Preserve the original file so Fix-CredHelper can restore it exactly, rather
# than guessing at whatever else was already in config.json (auths,
# currentContext, credHelpers, plugin config, aliases, and so on).
$backupPath = "$configFile.backup-credhelper-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Copy-Item -Path $configFile -Destination $backupPath -Force

# ------------------------------------------------------------------
# Point credsStore at a helper name that does not exist.
#
# "desktop" is the correct value on Windows - Docker Desktop installs the
# real docker-credential-desktop.exe into its bin directory and puts that
# directory on PATH.
# ------------------------------------------------------------------
try {
    $data = Get-Content $configFile -Raw | ConvertFrom-Json
} catch {
    # An unparseable config.json would make the break indistinguishable from
    # plain JSON corruption, which is a different scenario. Start clean.
    $data = [PSCustomObject]@{}
}

$data | Add-Member -MemberType NoteProperty -Name credsStore -Value "desktop-broken" -Force

[System.IO.File]::WriteAllText(
    $configFile,
    ($data | ConvertTo-Json -Depth 10),
    [System.Text.UTF8Encoding]::new($false))

Write-Host "  credsStore pointed at a non-existent credential helper"

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Backup saved: $backupPath"
Write-Host ""
Write-Host "Symptom: docker pull / docker login / docker push all fail immediately with"
Write-Host "  'error getting credentials - err: exec: \"docker-credential-desktop-broken\": executable file not found in %PATH%'"
