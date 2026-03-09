# fix_proxy.ps1 - Remove broken proxy configuration
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# The proxy break writes a bogus proxy address (192.0.2.1:8080, RFC 5737
# TEST-NET) to daemon.json and injects HTTP_PROXY / HTTPS_PROXY / NO_PROXY
# into the User-scope environment via [System.Environment]::SetEnvironmentVariable,
# which writes to HKCU:\Environment.
#
# This script reverses both changes and resets the lab state in
# $HOME\.docker-training-labs\config.json so troubleshootwinlab sees no active lab.

$ErrorActionPreference = "Stop"

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

$dockerConfig = Join-Path $HOME ".docker\daemon.json"

# --- Fix daemon.json ---
Write-Host "Checking daemon.json..."
if (Test-Path $dockerConfig) {
    $content = Get-Content $dockerConfig -Raw
    if ($content -match "invalid-proxy\.local|192\.0\.2\.\d+") {
        Write-Host "  Found broken proxy config"

        # Restore from the most recent backup if one exists, otherwise remove
        # the file entirely so Docker Desktop falls back to its defaults.
        $backups = Get-ChildItem -Path (Split-Path $dockerConfig) `
                                 -Filter "daemon.json.backup*" `
                                 -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            Copy-Item -Path $backups[0].FullName -Destination $dockerConfig -Force
            Write-Host "  Restored from backup: $($backups[0].Name)"
        } else {
            Remove-Item $dockerConfig -Force
            Write-Host "  Removed broken daemon.json (no backup found)"
        }
    } else {
        Write-Host "  daemon.json is clean"
    }
} else {
    Write-Host "  No daemon.json found"
}

# --- Fix User-scope environment variables ---
# The break script writes these via [System.Environment]::SetEnvironmentVariable
# at "User" scope, which persists to HKCU:\Environment. Setting them to $null
# at the same scope removes the registry entry entirely.
Write-Host ""
Write-Host "Checking User-scope environment variables..."

$proxyVars = @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy")
foreach ($var in $proxyVars) {
    $current = [System.Environment]::GetEnvironmentVariable($var, "User")
    if ($null -ne $current) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "User")
        Write-Host "  Cleared $var (was: $current)"
    }
}

# Also clear from the current process scope so the session reflects the fix
# immediately without requiring a terminal restart.
foreach ($var in $proxyVars) {
    [System.Environment]::SetEnvironmentVariable($var, $null, "Process")
}
Write-Host "  Process-scope proxy variables cleared"

Write-Host ""
Write-Host "Proxy configuration cleaned up"
Write-Host ""
Write-Host "IMPORTANT:"
Write-Host "  1. Restart Docker Desktop for daemon.json changes to take effect"
Write-Host "  2. Open a new terminal for User-scope variable changes to take effect"
Write-Host ""
Write-Host "To restart Docker Desktop:"
Write-Host "  1. Right-click the Docker icon in your taskbar"
Write-Host "  2. Select 'Restart'"
Write-Host "  3. Wait for Docker Desktop to fully restart"
Write-Host ""

# Test registry access
Write-Host "Testing registry access (may fail until Docker restarts)..."
docker pull hello-world 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Registry access working"
    docker rmi hello-world 2>&1 | Out-Null
} else {
    Write-Host "  Registry access not working yet (restart Docker Desktop)"
}

# Reset the lab state last, after the environment is repaired.
Reset-LabState
Write-Host "Lab state reset: no active scenario"
