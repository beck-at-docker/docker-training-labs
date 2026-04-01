# break_authconfig.ps1 - Simulates an org enforcement misconfiguration in
# Docker Desktop's settings store.
#
# Based on real support cases where Docker Desktop immediately signed users out
# after SSO because allowedOrgs was set to a URL-format value instead of a
# plain organization slug. Docker Desktop's org enforcement check matches
# against plain slugs only - a URL value never matches any real org, so every
# login attempt fires enforcement and triggers an immediate sign-out.
#
# The break does two things:
#
#   1. settings-store.json: writes a URL-format array to allowedOrgs
#      (e.g. ["https://hub.docker.com/u/required-org"]) instead of the correct
#      plain-slug format (e.g. ["required-org"]). The enforcement check runs
#      on sign-in and immediately signs the user out because no slug matches.
#
#   2. docker logout: clears stored Docker Hub credentials so the trainee is
#      forced to attempt sign-in and encounter the enforcement failure directly.
#
# Docker Desktop is restarted after the settings change so it reads the
# updated configuration before the trainee attempts to sign in.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
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
# Corrupt the allowedOrgs value in the settings store.
#
# The correct format is a JSON array of plain org slugs: ["my-org-name"].
# We write a URL-format value instead. Docker Desktop's enforcement check
# will never match this against any real org slug, so every sign-in
# attempt results in an immediate sign-out loop.
# ------------------------------------------------------------------
$backupPath = "${settingsStore}.backup-auth-${timestamp}"
Copy-Item $settingsStore $backupPath

$data = Get-Content $settingsStore -Raw | ConvertFrom-Json

# URL-format value - the correct format is just the org slug (e.g.
# "my-company"), not a full URL with scheme and path components.
$data | Add-Member -MemberType NoteProperty -Name allowedOrgs `
        -Value @("https://hub.docker.com/u/required-org") -Force

$data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8

Write-Host "  Settings store updated"

# ------------------------------------------------------------------
# Sign out of Docker Hub to force the sign-in prompt.
#
# docker logout removes the stored credential for the default registry
# via the Windows credential helper. After Docker Desktop restarts with
# the broken allowedOrgs config, the trainee will be prompted to sign in.
# Their attempt will trigger the enforcement check and immediate sign-out.
# ------------------------------------------------------------------
docker logout 2>&1 | Out-Null
Write-Host "  Docker Hub credentials cleared"

# ------------------------------------------------------------------
# Restart Docker Desktop so it reads the updated settings-store.json.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply settings..."

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
Write-Host "Symptom: Sign-in loop - SSO completes in browser but Docker Desktop immediately signs out"
