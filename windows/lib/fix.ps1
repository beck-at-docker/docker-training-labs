# lib/fix.ps1 - Scenario fix functions for Docker Desktop Training Labs (Windows)
#
# This file is a shared library. It is dot-sourced by:
#   - troubleshootwinlab.ps1  (via Invoke-FixCurrentLab, called from Abandon-Lab)
#   - scenarios/all.ps1       (Fix All trainer tool)
#
# Each Fix-* function is idempotent: running it on an already-fixed environment
# is safe and produces no harmful side effects.
#
# Scenario requirements at a glance:
#
#   Docker must be RUNNING:  DNS, PORT, BRIDGE, PROXY, PROXYFAIL
#   Docker must be STOPPED:  AUTHCONFIG
#   Docker state irrelevant: SSO (pipe API for proxy, no restart needed)
#
# PROXY, PROXYFAIL, and SSO use the backend pipe API while Docker is running.
# They fall back to editing settings-store.json if the pipe is unavailable,
# but that fallback requires a manual Docker Desktop restart.
#
# AUTHCONFIG writes registry.json to C:\ProgramData\DockerDesktop\ and needs
# Docker restarted so it picks up the new enforcement config on startup.
# The fix simply deletes registry.json and restarts Docker Desktop.
#
# Scenarios that operate via live iptables or container removal (DNS, BRIDGE,
# PORT) require Docker to be running and do not need a restart to take effect.
#
# IMPORTANT: Never use 'Set-Content -Encoding UTF8' for JSON files. PowerShell
# 5.x writes UTF-8 with a BOM (EF BB BF) that Go's JSON parser rejects. Use
# the Write-JsonFile helper below instead.

$settingsStore = "$env:APPDATA\Docker\settings-store.json"
$dockerExe     = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
$jobIdFile     = "$env:TEMP\port_squatter_8080_job.txt"

# Write-JsonFile - Write a string to a file as UTF-8 WITHOUT a BOM.
#
# PowerShell 5.x's 'Set-Content -Encoding UTF8' adds a BOM (bytes EF BB BF)
# at the start of the file. Go's encoding/json (used by Docker Desktop) does
# not handle BOM-prefixed input and fails with: "invalid character '\ufeff'
# looking for beginning of value". Docker Desktop then falls back to defaults
# or admin policy, silently discarding whatever we wrote.
#
# This function wraps [System.IO.File]::WriteAllText with an explicit
# BOM-free UTF-8 encoding. Use it for ALL JSON file writes in this project.
function Write-JsonFile {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# Invoke-DockerBackendAPI - Send a POST request to the Docker Desktop
# backend named pipe API. Used by fix functions to apply settings to
# the live daemon without requiring a Docker Desktop restart.
#
# Parameters:
#   Payload - hashtable to be serialised as JSON and sent as the body
#
# Returns $true on HTTP 200/204, $false on failure.
function Invoke-DockerBackendAPI {
    param([hashtable]$Payload)

    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".", "dockerBackendApiServer",
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None)
        $pipe.Connect(5000)

        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($json)
        $request = "POST /app/settings HTTP/1.0`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`n`r`n$json"
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($request)
        $pipe.Write($reqBytes, 0, $reqBytes.Length)
        $pipe.Flush()
        $pipe.WaitForPipeDrain()

        $reader   = New-Object System.IO.StreamReader($pipe)
        $response = $reader.ReadToEnd()
        $pipe.Close()

        $statusLine = ($response -split "`r`n")[0]
        return $statusLine -match "200|204"
    } catch {
        Write-Host "  Warning: Could not connect to Docker Desktop backend pipe: $_"
        return $false
    }
}


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

    Write-JsonFile -Path $Path -Content ($data | ConvertTo-Json -Depth 10)
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
# proxy keys to system mode. Then calls the backend pipe API to apply the
# restored settings to the live daemon immediately - no restart required.
# Also clears User-scope and Process-scope proxy environment variables
# injected by break_proxy.ps1.
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

    # Apply the restored settings to the live daemon via the backend pipe API.
    # This propagates the change immediately without requiring a Docker restart.
    Write-Host ""
    Write-Host "Applying restored proxy settings to live daemon..."
    $apiResult = Invoke-DockerBackendAPI -Payload @{
        vm = @{
            proxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
            containersProxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
        }
    }
    if ($apiResult) {
        Write-Host "  API call succeeded - proxy reset to system mode"
    } else {
        Write-Host "  API call failed - a Docker Desktop restart may be required"
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

# Fix-ProxyFail - Restore proxy settings via the backend pipe API.
#
# break_proxyfail.ps1 sets a loopback proxy (127.0.0.1:9753) via the backend
# pipe API. This function restores proxy mode to system via the same API
# while Docker Desktop is running.
#
# Falls back to restoring settings-store.json from backup if the pipe is
# unavailable. In that case Docker Desktop must be restarted manually.
#
# Does NOT require Stop-DockerDesktop - Docker Desktop must be running.
function Fix-ProxyFail {
    Write-Host "Removing broken loopback proxy configuration..."

    # Try the backend pipe API first (preferred - applies immediately).
    Write-Host "Restoring proxy settings via Docker Desktop backend API..."
    $apiResult = Invoke-DockerBackendAPI -Payload @{
        vm = @{
            proxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
            containersProxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
        }
    }

    if ($apiResult) {
        Write-Host "  API call succeeded - proxy reset to system mode"
    } else {
        Write-Host "  API call failed - falling back to file restore"
        # Fallback: restore settings-store.json from backup.
        # Docker Desktop must be restarted for the file change to take effect.
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
            Write-Host "  Settings store not found - nothing to restore"
        }
        Write-Host "  Docker Desktop must be restarted for the fix to take effect"
    }

    Write-Host ""
    Write-Host "Proxy failure configuration cleaned up"
}

# Fix-Sso - Remove the asymmetric ProxyExclude from settings-store.json.
#
# break_sso.ps1 sets a ProxyExclude list that covers the registry but not
# the SSO login endpoints, causing auth to fail while pulls still work.
# Restores from backup or resets proxy keys to system mode, then calls
# the backend pipe API to apply the change to the live daemon immediately.
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

    # Apply the restored settings to the live daemon via the backend pipe API.
    # This propagates the change immediately without requiring a Docker restart.
    Write-Host ""
    Write-Host "Applying restored proxy settings to live daemon..."
    $apiResult = Invoke-DockerBackendAPI -Payload @{
        vm = @{
            proxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
            containersProxy = @{
                mode    = @{ value = "system" }
                http    = @{ value = "" }
                https   = @{ value = "" }
                exclude = @{ value = "" }
            }
        }
    }
    if ($apiResult) {
        Write-Host "  API call succeeded - proxy reset to system mode"
    } else {
        Write-Host "  API call failed - a Docker Desktop restart may be required"
    }

    Write-Host ""
    Write-Host "SSO proxy configuration cleaned up"
    Write-Host "NOTE: Sign back in manually after proxy is cleared: docker login"
}

# Fix-AuthConfig - Delete the registry.json enforcement file created by the break.
#
# break_authconfig.ps1 creates C:\ProgramData\DockerDesktop\registry.json with
# allowedOrgs set to a wrong org slug ("acme-corp"), causing a sign-in loop.
# The file does not exist by default, so the fix simply removes it.
#
# Docker Desktop reads registry.json only on startup, so a restart is required
# after this fix. The CLI orchestrator handles the restart.
function Fix-AuthConfig {
    $registryJson = "C:\ProgramData\DockerDesktop\registry.json"

    Write-Host "Removing org enforcement configuration..."

    if (Test-Path $registryJson) {
        Remove-Item $registryJson -Force
        Write-Host "  Deleted registry.json"
    } else {
        Write-Host "  registry.json not found - nothing to fix"
    }

    Write-Host ""
    Write-Host "Org enforcement configuration removed"
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
