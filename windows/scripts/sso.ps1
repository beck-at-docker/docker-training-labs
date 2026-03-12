# sso.ps1 - Remove broken SSO proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_sso.ps1:
#   1. Restores settings-store.json from backup (or resets proxy keys to
#      "system" mode if no backup exists) and restarts Docker Desktop
#
# Note: docker logout cannot be reversed automatically. Sign back in
# manually after running this script.
#
# After repairing the environment, resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no
# active lab.

$ErrorActionPreference = "Stop"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

# Reset the training lab state file so the CLI sees no active scenario.
function Reset-LabState {
    $configFile = Join-Path $HOME ".docker-training-labs\config.json"
    if (-not (Test-Path $configFile)) { return }
    try {
        $data = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        $data = [PSCustomObject]@{}
    }
    $data | Add-Member -MemberType NoteProperty -Name current_scenario    -Value $null -Force
    $data | Add-Member -MemberType NoteProperty -Name scenario_start_time -Value $null -Force
    $data | ConvertTo-Json | Set-Content $configFile -Encoding UTF8
}

Write-Host "Removing broken SSO proxy configuration..."

# ------------------------------------------------------------------
# Fix settings-store.json
# ------------------------------------------------------------------
Write-Host "Checking Docker Desktop settings store..."

if (Test-Path $settingsStore) {
    $backupDir = Split-Path $settingsStore
    $backups   = Get-ChildItem -Path $backupDir `
                               -Filter "settings-store.json.backup-*" `
                               -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending

    if ($backups.Count -gt 0) {
        Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
        Write-Host "  Restored settings store from backup: $($backups[0].Name)"
    } else {
        Write-Host "  No backup found, resetting proxy keys to system mode"
        $data = Get-Content $settingsStore -Raw | ConvertFrom-Json

        foreach ($key in @("ProxyHTTP", "ProxyHTTPS", "ProxyExclude",
                           "ContainersProxyHTTP", "ContainersProxyHTTPS", "ContainersProxyExclude")) {
            $data.PSObject.Properties.Remove($key)
        }

        $data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "system" -Force
        $data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "system" -Force

        $data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8
        Write-Host "  Proxy keys reset to system mode"
    }
} else {
    Write-Host "  Settings store not found - nothing to fix"
}

# ------------------------------------------------------------------
# Restart Docker Desktop to apply the restored settings
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Restarting Docker Desktop to apply restored settings..."

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
} else {
    Write-Host "  Docker Desktop is running"
}

Write-Host ""
Write-Host "SSO proxy configuration cleaned up"
Write-Host ""
Write-Host "NOTE: Credentials were cleared by the break script and cannot be"
Write-Host "automatically restored. Sign back in:"
Write-Host "  docker login"
Write-Host "  or via the Docker Desktop GUI"
Write-Host ""

Reset-LabState
Write-Host "Lab state reset: no active scenario"
