# break_authconfig.ps1 - Simulates an org enforcement misconfiguration in
# Docker Desktop's sign-in enforcement file.
#
# Based on real support cases where an admin pushed a registry.json file via
# MDM with the wrong org slug. Docker Desktop reads registry.json on startup
# and enforces sign-in: the user must be a member of one of the listed orgs.
# If the slug doesn't match any org the user belongs to, Docker Desktop signs
# them out immediately after every login attempt.
#
# On Windows, Docker Desktop reads sign-in enforcement config from:
#   C:\ProgramData\DockerDesktop\registry.json
#
# This file does not exist by default - it is created by admins to enable
# org enforcement. Writing it requires admin privileges, which reflects how
# it would be deployed in a real environment (MDM or admin script).
#
# The break does two things:
#
#   1. docker logout: clears stored Docker Hub credentials while Docker Desktop
#      is still running, so the Windows credential helper can execute cleanly.
#
#   2. registry.json: creates the enforcement file with a wrong-but-valid org
#      slug ("acme-corp"). The trainee's account is not a member of this org,
#      so every sign-in attempt triggers enforcement and immediately signs
#      them out.
#
# Docker Desktop is restarted after registry.json is written so it picks up
# the new enforcement configuration.

$registryJson = "C:\ProgramData\DockerDesktop\registry.json"

Write-Host "Breaking Docker Desktop..."

# Verify Docker Desktop is running before touching anything
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

# ------------------------------------------------------------------
# Sign out of Docker Hub while Docker Desktop is still running.
#
# The Windows credential helper requires the Docker Desktop process to
# be running. Calling docker logout after DD is stopped silently fails,
# leaving the trainee signed in and unable to trigger the enforcement
# loop. Running logout here, while DD is confirmed running, ensures
# credentials are cleared before we restart.
# ------------------------------------------------------------------
docker logout 2>&1 | Out-Null
Write-Host "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Create registry.json with a wrong org slug.
#
# The trainee's account is not a member of "acme-corp", so enforcement
# fires on every sign-in attempt. We use a valid slug format (not a URL)
# because Docker Desktop validates slug format before enforcing - a
# malformed value is silently ignored rather than triggering sign-out.
#
# registry.json does not exist by default, so there is nothing to back
# up. The fix simply deletes the file.
#
# C:\ProgramData\DockerDesktop\ requires admin rights to write, so
# Docker Desktop cannot overwrite this file on startup - it persists
# across restarts.
# ------------------------------------------------------------------

# Use BOM-free UTF-8. PowerShell 5.x Set-Content -Encoding UTF8 writes a BOM
# that Go's json.Unmarshal rejects. WriteAllText with UTF8Encoding($false)
# produces clean BOM-free output.
[System.IO.File]::WriteAllText($registryJson, '{"allowedOrgs":["acme-corp"]}', [System.Text.UTF8Encoding]::new($false))

Write-Host "  registry.json created with wrong org slug"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the new registry.json.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply enforcement config..."

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
Write-Host "Symptom: Sign-in loop - login completes but Docker Desktop immediately signs out"
