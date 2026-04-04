# lib/fix.ps1 - Scenario fix functions for Docker Desktop Training Labs (Windows)
#
# This file is a shared library. It is dot-sourced by:
#   - troubleshootwinlab.ps1  (via Invoke-FixCurrentLab, called from Abandon-Lab)
#   - scenarios/all.ps1       (Fix All trainer tool)
#
# Each Fix-* function is idempotent: running it on an already-fixed environment
# is safe and produces no harmful side effects.
#
# Scenarios that write to settings-store.json (Proxy, ProxyFail, SSO,
# AuthConfig) MUST be called after Stop-DockerDesktop. Docker flushes its
# in-memory configuration back to settings-store.json on a clean shutdown,
# which would overwrite any changes written while the daemon was running.
#
# Scenarios that operate via live iptables or container removal (DNS, Bridge,
# Ports) require Docker to be running and do not need a restart to take effect.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$dockerExe     = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
$jobIdFile     = "$env:TEMP\port_squatter_8080_job.txt"

# Stop-DockerDesktop - Force-stop Docker Desktop and wait for the process to exit.
#
# Uses Stop-Process -Force to kill the process immediately, then polls for up
# to ~15 seconds. Unlike a graceful quit, force-kill prevents Docker from
# flushing its in-memory config back to settings-store.json on exit, which is
# exactly what we want before writing fixes to that file.
function Stop-DockerDesktop {
    Write-Host "Stopping Docker Desktop..."
    $proc = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | Stop-Process -Force
        $waited = 0
        while ((Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) -and $waited -lt 15) {
            Start-Sleep -Seconds 1
            $waited++
        }
    }
    Write-Host "  Docker Desktop stopped"
}

# Reset-ProxyKeys - Remove manual proxy keys from settings-store.json and
# set both proxy mode fields to "system". Shared by Fix-Proxy, Fix-ProxyFail,
# and Fix-Sso when no scenario-specific backup is available.
function Reset-ProxyKeys {
    param([string]$Path)

    $data = Get-Content $Path -Raw | ConvertFrom-Json

    foreach ($key in @("ProxyHTTP", "ProxyHTTPS", "ProxyExclude",
                       "OverrideProxyHTTP", "OverrideProxyHTTPS",
                       "ContainersProxyHTTP", "ContainersProxyHTTPS", "ContainersProxyExclude",
                       "ContainersOverrideProxyHTTP", "ContainersOverrideProxyHTTPS")) {
        $data.PSObject.Properties.Remove($key)
    }

    $data | Add-Member -MemberType NoteProperty -Name ProxyHTTPMode           -Value "system" -Force
    $data | Add-Member -MemberType NoteProperty -Name ContainersProxyHTTPMode -Value "system" -Force

    $data | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
}

# Fix-Bridge - Restore the Docker bridge network.
#
# Removes the lab's test containers and the iptables DROP rule injected into
# the Docker VM by break_bridge.ps1. Requires a running Docker daemon.
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
        Write-Host "  iptables restore failed - a Docker Desktop restart should clear it"
    }

    Write-Host ""
    Write-Host "Verifying network connectivity..."
    docker run --rm alpine:latest ping -c 2 8.8.8.8 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Internet connectivity restored"
    } else {
        Write-Host "  Internet connectivity still broken"
    }
}

# Fix-Dns - Remove the iptables DNS-block rules from inside the Docker VM.
#
# break_dns.ps1 injects DROP rules for UDP/TCP port 53 in the VM's OUTPUT
# chain. This function removes them via nsenter. Requires a running daemon.
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
        Write-Host "  DNS resolution restored"
        docker rmi hello-world 2>&1 | Out-Null
    } else {
        Write-Host "  DNS still broken - a Docker Desktop restart should clear this"
    }
}

# Fix-Proxy - Remove the bogus manual proxy from settings-store.json and
# clear proxy environment variables.
#
# Restores from a scenario-specific backup if one exists; otherwise resets
# proxy keys to system mode. Also clears User-scope and Process-scope proxy
# environment variables injected by break_proxy.ps1.
#
# MUST be called after Stop-DockerDesktop.
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

# Fix-ProxyFail - Remove the loopback proxy address from settings-store.json.
#
# break_proxyfail.ps1 sets ProxyHTTP/HTTPS to 127.0.0.1:9753, causing an
# immediate connection-refused error on every pull. Restores from backup or
# resets to system mode.
#
# MUST be called after Stop-DockerDesktop.
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

# Fix-Sso - Remove the asymmetric ProxyExclude from settings-store.json.
#
# break_sso.ps1 sets a ProxyExclude list that covers the registry but not
# the SSO login endpoints, causing auth to fail while pulls still work.
# Restores from backup or resets proxy keys to system mode.
#
# MUST be called after Stop-DockerDesktop.
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
    Write-Host "NOTE: Sign back in manually after Docker Desktop restarts: docker login"
}

# Fix-AuthConfig - Remove the corrupt allowedOrgs value from settings-store.json.
#
# break_authconfig.ps1 sets allowedOrgs to a URL-format value instead of a
# plain org slug, causing the sign-in loop. Restores from backup or removes
# the allowedOrgs key entirely.
#
# MUST be called after Stop-DockerDesktop.
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
    Write-Host "NOTE: Sign back in manually after Docker Desktop restarts: docker login"
}

# Fix-Ports - Remove port-squatter containers and background TCP listener jobs.
#
# break_ports.ps1 starts several containers and a background PowerShell job
# holding a TcpListener on port 8080. This removes them so the ports are
# available again. Requires a running Docker daemon.
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
