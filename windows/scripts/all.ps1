# all.ps1 - Restore all Docker Desktop systems
# FOR DEVELOPMENT/TESTING ONLY - Not for trainees
#
# Standalone script: all fix logic is inlined. No external fix scripts required.
# Runs every section regardless of individual failures, performs a single
# Docker Desktop restart at the end, then prints a clear pass/fail summary.

# ===========================================================================
# Configuration
# ===========================================================================

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$dockerExe     = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
$jobIdFile     = "$env:TEMP\port_squatter_8080_job.txt"

# ===========================================================================
# Shared helpers
# ===========================================================================

# Reset-LabState - Clear the active scenario from config.json.
# Called once at the end after all fixes have been applied.
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

# Invoke-Section <label> <scriptblock>
# Runs the given scriptblock, tracks pass/fail, never exits early.
function Invoke-Section {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "--- $Label ---"
    try {
        & $Action
        Write-Host "  -> OK"
    }
    catch {
        Write-Host "  -> FAILED: $_"
        $script:failedSteps += $Label
    }
    Write-Host ""
    Write-Host "=========================================="
}

# Reset-ProxyKeys - Remove manual proxy keys from settings-store.json and
# set both proxy mode fields to "system". Shared by proxy, proxyfail, and sso.
function Reset-ProxyKeys {
    param([string]$Path)

    $data = Get-Content $Path -Raw | ConvertFrom-Json

    foreach ($key in @("ProxyHTTP", "ProxyHTTPS", "ProxyExclude",
                       "ContainersProxyHTTP", "ContainersProxyHTTPS", "ContainersProxyExclude")) {
        $data.PSObject.Properties.Remove($key)
    }

    $data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "system" -Force
    $data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "system" -Force

    $data | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
}

# ===========================================================================
# Fix functions - one per scenario
# ===========================================================================

# -- [1/7] Bridge Network ----------------------------------------------------
function Fix-Bridge {
    Write-Host "Restoring Docker bridge network..."

    Write-Host "Removing test containers..."
    docker rm -f broken-web 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  Removed broken-web" }
    docker rm -f broken-app 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  Removed broken-app" }

    Write-Host ""
    Write-Host "Restoring iptables rules..."
    docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i sh -c `
        'iptables -D FORWARD -i docker0 -j DROP 2>/dev/null || true; echo "DROP rule removed"'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  iptables restore failed - the consolidated restart should clear it"
    }

    Write-Host ""
    Write-Host "Verifying network connectivity..."
    docker run --rm alpine:latest ping -c 2 8.8.8.8 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Internet connectivity working"
    } else {
        Write-Host "  Internet connectivity still broken"
    }
}

# -- [2/7] DNS Resolution ----------------------------------------------------
function Fix-Dns {
    Write-Host "Fixing Docker Desktop DNS..."

    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop is not running"
    }

    # Use a semicolon-delimited string - PS5.1 argument passing to external
    # commands is unreliable with newlines in strings.
    $iptablesCmd = "iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true; " +
                   "iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true"

    docker run --rm --privileged --pid=host alpine:latest `
        nsenter -t 1 -m -u -n -i sh -c $iptablesCmd 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to access the Docker VM via nsenter"
    }

    Write-Host ""
    Write-Host "Verifying DNS resolution..."
    docker pull hello-world 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  DNS resolution working"
        docker rmi hello-world 2>&1 | Out-Null
    } else {
        Write-Host "  DNS still broken - the consolidated restart should clear this"
    }
}

# -- [3/7] Proxy Configuration -----------------------------------------------
function Fix-Proxy {
    Write-Host "Removing broken proxy configuration..."

    Write-Host "Checking Docker Desktop settings store..."
    if (Test-Path $settingsStore) {
        $backupDir = Split-Path $settingsStore
        $backups   = Get-ChildItem -Path $backupDir `
                                   -Filter "settings-store.json.backup-proxy-*" `
                                   -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
            Write-Host "  Restored settings store from backup: $($backups[0].Name)"
        } else {
            Write-Host "  No backup found, resetting proxy keys to system mode"
            Reset-ProxyKeys -Path $settingsStore
            Write-Host "  Proxy keys reset to system mode"
        }
    } else {
        Write-Host "  Settings store not found - nothing to fix"
    }

    Write-Host ""
    Write-Host "Clearing proxy environment variables..."
    $proxyVars = @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy")
    foreach ($var in $proxyVars) {
        $current = [System.Environment]::GetEnvironmentVariable($var, "User")
        if ($null -ne $current) {
            [System.Environment]::SetEnvironmentVariable($var, $null, "User")
            Write-Host "  Cleared $var from User scope (was: $current)"
        }
        [System.Environment]::SetEnvironmentVariable($var, $null, "Process")
    }
    Write-Host "  Process-scope proxy variables cleared"

    Write-Host ""
    Write-Host "Proxy configuration cleaned up"
    Write-Host "Open a new terminal for User-scope variable changes to take effect."
}

# -- [4/7] Proxy Failure Simulation ------------------------------------------
function Fix-ProxyFail {
    Write-Host "Removing broken loopback proxy configuration..."

    Write-Host "Checking Docker Desktop settings store..."
    if (Test-Path $settingsStore) {
        $backupDir = Split-Path $settingsStore
        $backups   = Get-ChildItem -Path $backupDir `
                                   -Filter "settings-store.json.backup-proxyfail-*" `
                                   -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
            Write-Host "  Restored settings store from backup: $($backups[0].Name)"
        } else {
            Write-Host "  No backup found, resetting proxy keys to system mode"
            Reset-ProxyKeys -Path $settingsStore
            Write-Host "  Proxy keys reset to system mode"
        }
    } else {
        Write-Host "  Settings store not found - nothing to fix"
    }

    Write-Host ""
    Write-Host "Proxy failure configuration cleaned up"
}

# -- [5/7] SSO Configuration -------------------------------------------------
function Fix-Sso {
    Write-Host "Removing broken SSO proxy configuration..."

    Write-Host "Checking Docker Desktop settings store..."
    if (Test-Path $settingsStore) {
        $backupDir = Split-Path $settingsStore
        $backups   = Get-ChildItem -Path $backupDir `
                                   -Filter "settings-store.json.backup-sso-*" `
                                   -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
            Write-Host "  Restored settings store from backup: $($backups[0].Name)"
        } else {
            Write-Host "  No backup found, resetting proxy keys to system mode"
            Reset-ProxyKeys -Path $settingsStore
            Write-Host "  Proxy keys reset to system mode"
        }
    } else {
        Write-Host "  Settings store not found - nothing to fix"
    }

    Write-Host ""
    Write-Host "SSO proxy configuration cleaned up"
    Write-Host "NOTE: Sign back in manually: docker login"
}

# -- [6/7] Auth Config Enforcement -------------------------------------------
function Fix-AuthConfig {
    Write-Host "Removing broken allowedOrgs configuration..."

    Write-Host "Checking Docker Desktop settings store..."
    if (Test-Path $settingsStore) {
        $backupDir = Split-Path $settingsStore
        $backups   = Get-ChildItem -Path $backupDir `
                                   -Filter "settings-store.json.backup-auth-*" `
                                   -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            Copy-Item -Path $backups[0].FullName -Destination $settingsStore -Force
            Write-Host "  Restored settings store from backup: $($backups[0].Name)"
        } else {
            # No backup - remove the allowedOrgs key entirely, which disables
            # org enforcement and allows any authenticated user to proceed.
            Write-Host "  No backup found, removing allowedOrgs key"
            $data = Get-Content $settingsStore -Raw | ConvertFrom-Json
            $data.PSObject.Properties.Remove("allowedOrgs")
            $data | ConvertTo-Json -Depth 10 | Set-Content $settingsStore -Encoding UTF8
            Write-Host "  allowedOrgs key removed"
        }
    } else {
        Write-Host "  Settings store not found - nothing to fix"
    }

    Write-Host ""
    Write-Host "allowedOrgs configuration cleaned up"
    Write-Host "NOTE: Sign back in manually: docker login"
}

# -- [7/7] Port Conflicts ----------------------------------------------------
function Fix-Ports {
    Write-Host "Cleaning up port conflicts..."

    Write-Host "Removing port squatter containers..."
    $containers = @("port-squatter-80", "port-squatter-443", "port-squatter-3306", "background-db")
    foreach ($name in $containers) {
        docker rm -f $name 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  Removed $name" }
    }

    Write-Host ""
    Write-Host "Stopping background TCP listener on port 8080..."
    if (Test-Path $jobIdFile) {
        $jobId = Get-Content $jobIdFile -ErrorAction SilentlyContinue
        if ($jobId) {
            Stop-Job  -Id $jobId -ErrorAction SilentlyContinue
            Remove-Job -Id $jobId -Force -ErrorAction SilentlyContinue
            Write-Host "  Stopped job $jobId"
        }
        Remove-Item $jobIdFile -ErrorAction SilentlyContinue
        Write-Host "  Removed job ID file"
    } else {
        Write-Host "  No job ID file found - checking for orphaned TcpListener jobs..."
        # Narrow scope: only stop jobs whose command block contains TcpListener,
        # which is the signature of the port squatter job.
        Get-Job | Where-Object { $_.State -eq "Running" -and $_.Command -like "*TcpListener*" } | ForEach-Object {
            Stop-Job  -Id $_.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Host "  Stopped orphaned TcpListener job $($_.Id)"
        }
    }

    Write-Host ""
    Write-Host "Port cleanup complete"
}

# ===========================================================================
# Main
# ===========================================================================

Write-Host "=========================================="
Write-Host "Restoring ALL Docker Desktop Systems"
Write-Host "=========================================="
Write-Host ""
Write-Host "This will fix:"
Write-Host "  1. Bridge Network"
Write-Host "  2. DNS Resolution"
Write-Host "  3. Proxy Configuration"
Write-Host "  4. Proxy Failure Simulation"
Write-Host "  5. SSO Configuration"
Write-Host "  6. Auth Config Enforcement"
Write-Host "  7. Port Conflicts"
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -notmatch "^[yY]$") {
    Write-Host "Cancelled."
    exit 0
}

Write-Host ""
Write-Host "=========================================="

# Tracks which steps failed so we can report clearly at the end.
$failedSteps = @()

# Fix bridge first (iptables rules affect all container networking),
# then DNS, then settings-store.json scenarios together (proxy, proxyfail,
# sso, authconfig) before a single Docker Desktop restart, ports last.
Invoke-Section "[1/7] Bridge Network"           { Fix-Bridge }
Invoke-Section "[2/7] DNS Resolution"           { Fix-Dns }
Invoke-Section "[3/7] Proxy Configuration"      { Fix-Proxy }
Invoke-Section "[4/7] Proxy Failure Simulation" { Fix-ProxyFail }
Invoke-Section "[5/7] SSO Configuration"        { Fix-Sso }
Invoke-Section "[6/7] Auth Config Enforcement"  { Fix-AuthConfig }
Invoke-Section "[7/7] Port Conflicts"           { Fix-Ports }

# ------------------------------------------------------------------
# Consolidated Docker Desktop restart
# ------------------------------------------------------------------
# proxy, proxyfail, sso, and authconfig all write to settings-store.json.
# Restart Docker Desktop once here to apply all accumulated changes.
Write-Host ""
Write-Host "--- Restarting Docker Desktop ---"
Write-Host ""

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

if (Test-Path $dockerExe) {
    Start-Process $dockerExe
} else {
    Write-Host "  Warning: Could not find Docker Desktop.exe - please start it manually"
    $failedSteps += "Docker Desktop restart"
}

Write-Host "Waiting for Docker Desktop to restart..."
$dockerReady = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
        break
    }
}

if (-not $dockerReady) {
    Write-Host "  Warning: Docker Desktop did not come back within 120s"
    $failedSteps += "Docker Desktop restart"
} else {
    Write-Host "  Docker Desktop is running"
    Write-Host ""
    Write-Host "Verifying registry access..."
    docker pull hello-world 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Registry access working"
        docker rmi hello-world 2>&1 | Out-Null
    } else {
        Write-Host "  Registry access not working - check Docker Desktop status"
        $failedSteps += "Registry access verification"
    }
}

Write-Host ""
Write-Host "=========================================="

# Clear lab state now that all fixes have been applied.
Reset-LabState
Write-Host "Lab state reset: no active scenario"

Write-Host ""
Write-Host "=========================================="

if ($failedSteps.Count -eq 0) {
    Write-Host "All Systems Restored"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Docker Desktop has been restarted. Verify everything is working:"
    Write-Host "  docker pull hello-world"
    Write-Host "  docker run --rm alpine:latest ping -c 2 google.com"
    Write-Host "  docker run -p 8080:80 nginx:alpine"
    Write-Host ""
    exit 0
} else {
    Write-Host "Restore completed with errors"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "The following steps failed:"
    foreach ($step in $failedSteps) {
        Write-Host "  - $step"
    }
    Write-Host ""
    Write-Host "Review the output above for details on each failure."
    Write-Host ""
    exit 1
}
