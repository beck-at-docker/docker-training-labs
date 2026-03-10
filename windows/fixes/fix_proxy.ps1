# fix_proxy.ps1 - Remove broken proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Reverses the changes made by break_proxy.ps1:
#   1. Restores settings-store.json from backup (or resets proxy keys to
#      "system" mode if no backup exists) and restarts Docker Desktop
#   2. Clears the bogus HTTP_PROXY / HTTPS_PROXY / NO_PROXY from both
#      User-scope (HKCU:\Environment) and the current process
#
# After repairing the environment, resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no
# active lab.

$ErrorActionPreference = "Stop"

$settingsStore = "$env:APPDATA\Docker\settings-store.json"

# Reset the training lab state file so the CLI sees no active scenario.
# Mirrors the logic in lib/state.ps1 without requiring it to be dot-sourced.
# Uses Add-Member -Force to set properties on the PSCustomObject, which is
# required in PS5.1 (direct property assignment on ConvertFrom-Json objects
# is unreliable).
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

Write-Host "Removing broken proxy configuration..."

# ------------------------------------------------------------------
# Fix settings-store.json
# ------------------------------------------------------------------
Write-Host "Checking Docker Desktop settings store..."

if (Test-Path $settingsStore) {
    # Look for the most recent backup created by break_proxy.ps1
    $backupDir = Split-Path $settingsStore
    $backups = Get-ChildItem -Path $backupDir `
                             -Filter "settings-store.json.backup-*" `
                             -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending

    if ($backups.Count -gt 0) {
        Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
        Write-Host "  Restored settings store from backup: $($backups[0].Name)"
    } else {
        # No backup - reset the proxy keys to system mode
        Write-Host "  No backup found, resetting proxy keys to system mode"
        $data = Get-Content $settingsStore -Raw | ConvertFrom-Json

        foreach ($key in @("ProxyHTTP", "ProxyHTTPS", "ProxyExclude",
                           "ContainersProxyHTTP", "ContainersProxyHTTPS", "ContainersProxyExclude")) {
            # Remove the property if present - PSCustomObject doesn't have Remove(),
            # so we rebuild without the key using Select-Object exclusion
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
# Clear User-scope and process-scope proxy environment variables
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Clearing proxy environment variables..."

$proxyVars = @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy")
foreach ($var in $proxyVars) {
    $current = [System.Environment]::GetEnvironmentVariable($var, "User")
    if ($null -ne $current) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "User")
        Write-Host "  Cleared $var from User scope (was: $current)"
    }
    # Also clear from current process so this session reflects the fix
    [System.Environment]::SetEnvironmentVariable($var, $null, "Process")
}
Write-Host "  Process-scope proxy variables cleared"

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

if ($ready) {
    Write-Host ""
    Write-Host "Verifying registry access..."
    docker pull hello-world 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Registry access working"
        docker rmi hello-world 2>&1 | Out-Null
    } else {
        Write-Host "  Registry access not working - check Docker Desktop status"
    }
} else {
    Write-Host "  Warning: Docker Desktop did not come back within 60s"
}

Write-Host ""
Write-Host "Proxy configuration cleaned up"
Write-Host "Open a new terminal for User-scope variable changes to take effect."
Write-Host ""

# Reset the lab state last, after the environment is repaired.
Reset-LabState
Write-Host "Lab state reset: no active scenario"
