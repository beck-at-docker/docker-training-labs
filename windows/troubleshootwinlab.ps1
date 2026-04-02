# troubleshootwinlab.ps1 - Main training lab CLI (Windows / WSL2 backend)
#
# Run with: powershell -ExecutionPolicy Bypass -File troubleshootwinlab.ps1 [options]
# Or via the cmd shim installed by install.ps1: troubleshootwinlab [options]
#
# Architecture overview
# ---------------------
# This script is the single entry point trainees interact with. Everything
# else is support infrastructure:
#
#   lib\colors.ps1    - Write-Blue/Green/Yellow/Red console output helpers
#   lib\state.ps1     - Read/write $STATE_DIR\config.json via ConvertFrom-Json
#   lib\grading.ps1   - Append rows to $STATE_DIR\grades.csv
#
#   scenarios\break_<n>.ps1 - Deliberately corrupt Docker Desktop
#   tests\test_<n>.ps1      - Verify the scenario has been fixed
#
# Lab lifecycle
# -------------
#   1. Trainee selects a lab; Start-Lab runs scenarios\break_<n>.ps1 in a
#      child PowerShell process and records the scenario name and start
#      time in config.json via lib\state.ps1
#   2. Trainee diagnoses and fixes Docker Desktop manually
#   3. --check runs tests\test_<n>.ps1 in a child process, captures output,
#      parses the structured footer, records the grade, and prints feedback
#   4. config.json is cleared so a new lab can be started
#
# Output contract (tests\test_*.ps1 footer, parsed by Check-Lab)
# -------------------------------------------------------------
#   Score: <n>%
#   Tests Passed: <n>    <- written by Generate-Report in test_framework.ps1
#   Tests Failed: <n>    <- written by Generate-Report in test_framework.ps1
#
# Note on child process execution
# --------------------------------
# Break and test scripts are run via '& powershell -ExecutionPolicy Bypass
# -File <path>' rather than dot-sourcing. This isolates their side effects
# and means $LASTEXITCODE reflects the script's exit code reliably.

param(
    [string]$Action = ""
)

# Configuration
$INSTALL_DIR  = "$env:ProgramData\docker-training-labs"
$STATE_DIR    = "$env:USERPROFILE\.docker-training-labs"
$CONFIG_FILE  = "$STATE_DIR\config.json"
$GRADES_FILE  = "$STATE_DIR\grades.csv"
$REPORTS_DIR  = "$STATE_DIR\reports"

# Source library functions
. "$INSTALL_DIR\lib\colors.ps1"
. "$INSTALL_DIR\lib\state.ps1"
. "$INSTALL_DIR\lib\grading.ps1"
. "$INSTALL_DIR\lib\fix.ps1"

# ------------------------------------------------------------------
function Show-Banner {
    Clear-Host
    Write-Blue "=========================================="
    Write-Host "Docker Desktop Training Labs"
    Write-Host "Break-Fix Troubleshooting Practice"
    Write-Blue "=========================================="
    Write-Host ""
}

# ------------------------------------------------------------------
function Show-MainMenu {
    Show-Banner
    $current = Get-CurrentScenario

    if ($current -and $current -ne "null") {
        Write-Yellow "WARNING: You currently have an active lab: $current"
        Write-Host ""
        Write-Host "1. Continue working on current lab"
        Write-Host "2. Submit current lab for grading"
        Write-Host "3. Abandon current lab and start new (requires manual Docker Desktop restart)"
        Write-Host "4. View my report card"
        Write-Host "0. Exit"
    } else {
        Write-Host "Select a training lab:"
        Write-Host ""
        Write-Host "1. Container Connections"
        Write-Host ""
        Write-Host "2. Port Problems"
        Write-Host ""
        Write-Host "3. Pull Problems"
        Write-Host ""
        Write-Host "4. Login Problems"
        Write-Host ""
        Write-Host "5. View my report card"
        Write-Host "0. Exit"
    }

    Write-Host ""
    Write-Blue "=========================================="
}

# ------------------------------------------------------------------
function Show-LabInstructions {
    param([string]$Lab)
    switch ($Lab) {
        "PORT" {
            Write-Host @"
Problem: Containers fail to bind to common ports

When you try to start containers that need standard ports
(80, 443, 3306, 5432, 8080), you get "address already in use"
errors.

Symptoms you should observe:
  - docker run -p 80:80 nginx:alpine fails with port allocation error
  - Multiple ports are mysteriously occupied
  - Some blocking containers may be hard to find

Diagnostic Commands to Try:
  docker ps -a
  netstat -ano | findstr LISTENING
  docker ps -a --filter "name=."

Note: not all port conflicts come from Docker containers.
Some may be Windows host processes - check netstat output carefully.

Fix it by identifying and removing port conflicts!
"@
        }
        "SSO" {
            Write-Host @"
Problem: Docker Desktop keeps signing you out

After starting Docker Desktop, you find yourself signed out.
When you try to sign back in using SSO, the browser opens and
you authenticate successfully - but Docker Desktop immediately
signs you out again.

Symptoms you should observe:
  - Docker Desktop shows you as signed out
  - docker info shows no Username field
  - Surprisingly, docker pull still works for public images
  - SSO loop: browser auth succeeds but Desktop signs out

The fact that pulls work but login doesn't is the key clue.
Something is selectively blocking certain network destinations
while leaving others reachable.

Diagnostic Commands to Try:
  docker info | Select-String username
  docker pull alpine:latest
  cat `$env:APPDATA\Docker\settings-store.json
  [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'User')

Look for:
  - ProxyHTTPMode set to "manual" with an unroutable proxy address
  - A ProxyExclude list covering registries but NOT login endpoints
  - The asymmetry: what works (pulls) vs. what doesn't (auth)

Fix the proxy config so auth endpoints are reachable, then sign
back in and run troubleshootwinlab --check.
"@
        }
        "PROXY" {
            Write-Host @"
Problem: Docker cannot reach external registries

Your Docker Desktop cannot pull images or access external
resources. This is likely due to proxy misconfiguration.

Symptoms you should observe:
  - docker pull fails with a proxy connection error
  - Containers can't reach the internet
  - Host machine internet access works fine

On Windows, proxy config lives in two places:
  - Docker Desktop settings store (Settings > Resources > Proxies)
  - User-scope environment variables (HTTP_PROXY, HTTPS_PROXY)

Diagnostic Commands to Try:
  docker pull hello-world
  docker info | Select-String proxy
  cat `$env:APPDATA\Docker\settings-store.json
  [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'User')

Look for:
  - ProxyHTTPMode set to "manual" with an unroutable proxy address
  - HTTP_PROXY / HTTPS_PROXY set in User-scope environment

Fix both layers to fully resolve the issue!
"@
        }
        "DNS" {
            Write-Host @"
Problem: docker pull fails with a DNS write error

The Docker daemon cannot resolve external hostnames. Image pulls
fail immediately with an error like:

  write udp ...: write: operation not permitted

Your Windows host DNS works fine. Interestingly, nslookup inside
a container may also appear to work. The daemon and containers
use different DNS paths - that discrepancy is your first clue.

Symptoms you should observe:
  - docker pull fails with "write: operation not permitted"
  - Error references a DNS lookup on an internal IP (e.g. 192.168.65.x)
  - Host machine DNS works fine
  - docker run --rm alpine:latest nslookup google.com may succeed

Diagnostic Commands to Try:
  docker pull hello-world
  docker info | Select-String dns
  cat $env:USERPROFILE\.docker\daemon.json
  docker run --rm alpine:latest nslookup google.com

If config looks clean, think about what sits between the daemon
and the network. Check whether traffic is being blocked at a
lower level inside the Docker VM:

  docker run --rm --privileged --pid=host alpine:latest ``
    nsenter -t 1 -m -u -n -i sh -c 'iptables -L OUTPUT -n -v'

Restarting Docker Desktop will clear the problem as a last
resort, but try to find and remove the root cause first.
"@
        }
    }
}

# ------------------------------------------------------------------
function Start-Lab {
    param([int]$LabNumber)

    $labName    = $null
    $breakScript = $null

    switch ($LabNumber) {
        1 {
            $labName     = "DNS"    # -> scenarios\break_dns.ps1, tests\test_dns.ps1
            $breakScript = "$INSTALL_DIR\scenarios\break_dns.ps1"
        }
        2 {
            $labName     = "PORT"   # -> scenarios\break_ports.ps1, tests\test_port.ps1
            $breakScript = "$INSTALL_DIR\scenarios\break_ports.ps1"
        }
        3 {
            $labName     = "PROXY"  # -> scenarios\break_proxy.ps1, tests\test_proxy.ps1
            $breakScript = "$INSTALL_DIR\scenarios\break_proxy.ps1"
        }
        4 {
            $labName     = "SSO"    # -> scenarios\break_sso.ps1, tests\test_sso.ps1
            $breakScript = "$INSTALL_DIR\scenarios\break_sso.ps1"
        }
        default {
            Write-Red "Invalid lab selection"
            return
        }
    }

    Show-Banner
    Write-Yellow "Starting Lab: $labName"
    Write-Host ""

    $confirm = Read-Host "This will break your Docker Desktop environment. Continue? (y/N)"
    if ($confirm -notmatch "^[yY]$") {
        Write-Host "Cancelled."
        return
    }

    Write-Host ""
    Write-Host "Breaking Docker Desktop..."

    & powershell -ExecutionPolicy Bypass -File $breakScript
    if ($LASTEXITCODE -ne 0) {
        Write-Red "Failed to break the environment. Check that Docker Desktop is running."
        return
    }

    Set-CurrentScenario $labName
    Set-ScenarioStartTime ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    Show-Banner
    Write-Green "Lab Started: $labName"
    Write-Host ""
    Write-Blue "=========================================="
    Write-Host "Your Mission"
    Write-Blue "=========================================="
    Show-LabInstructions $labName
    Write-Host ""
    Write-Blue "=========================================="
    Write-Host "When You're Done"
    Write-Blue "=========================================="
    Write-Host ""
    Write-Host "When you think you've fixed the issue, run:"
    Write-Green "  troubleshootwinlab --check"
    Write-Host ""
    Write-Host "This will test your fix and provide a score."
    Write-Host ""
}

# ------------------------------------------------------------------
# Check-Lab - Run the test script for the active scenario and record a grade
#
# Runs the test script in a child process and captures all output as an
# array of strings. Parses the structured footer lines, records the grade,
# displays the full output, then asks whether to try another lab.
#   - Yes: returns normally so Main()'s while loop redraws the menu
#   - No:  exits the process
function Check-Lab {
    $current = Get-CurrentScenario
    if (-not $current -or $current -eq "null") {
        Write-Red "No active lab. Start a lab first."
        exit 1
    }

    Show-Banner
    Write-Yellow "Testing your fix for: $current"
    Write-Host ""
    Write-Host "Running diagnostic tests..."
    Write-Host ""

    # Run the test script in a child process. $current.ToLower() maps the
    # stored scenario name (e.g. "DNS") to the test filename (test_dns.ps1).
    # 2>&1 merges stderr into the captured output array so nothing is lost.
    $testScript = "$INSTALL_DIR\tests\test_$($current.ToLower()).ps1"
    $testOutput = & powershell -ExecutionPolicy Bypass -File $testScript 2>&1

    # Parse the structured footer written by the test script. Select-Object
    # -Last 1 guards against any accidental duplicate matches earlier in output.
    $score       = ($testOutput | Select-String "^Score: (\d+)%"   | Select-Object -Last 1).Matches.Groups[1].Value
    $testsPassed = ($testOutput | Select-String "^Tests Passed: (\d+)").Matches.Groups[1].Value
    $testsFailed = ($testOutput | Select-String "^Tests Failed: (\d+)").Matches.Groups[1].Value

    $score       = if ($score) { [int]$score } else { 0 }
    $testsPassed = if ($testsPassed) { [int]$testsPassed } else { 0 }
    $testsFailed = if ($testsFailed) { [int]$testsFailed } else { 0 }

    $startTime   = Get-ScenarioStartTime
    $endTime     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $durationSec = $endTime - $startTime
    $durationMin = [int]($durationSec / 60)

    Show-Banner
    Write-Blue "=========================================="
    Write-Host "Lab Results: $current"
    Write-Blue "=========================================="
    Write-Host ""
    $testOutput | Write-Host
    Write-Host ""

    # Save report
    if (-not (Test-Path $REPORTS_DIR)) { New-Item -ItemType Directory -Force -Path $REPORTS_DIR | Out-Null }
    $reportFile = "$REPORTS_DIR\${current}_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $testOutput | Set-Content $reportFile

    # Record grade
    Record-Grade $env:USERNAME $current $score $durationSec

    Write-Blue "=========================================="
    Write-Host "Feedback"
    Write-Blue "=========================================="
    Write-Host ""
    Write-Host "Time taken:    $durationMin minutes"
    Write-Host "Tests passed:  $testsPassed"
    Write-Host "Tests failed:  $testsFailed"
    Write-Host ""

    if ($score -ge 90)    { Write-Green "Excellent work! You're ready for production support on this topic." }
    elseif ($score -ge 80){ Write-Green "Good job! Review the failed tests to improve further." }
    elseif ($score -ge 70){ Write-Yellow "Passing, but you missed some key points. Consider trying again." }
    else                  { Write-Red   "The issue wasn't fully resolved. Review the diagnostic steps and retry." }

    Write-Host ""
    Write-Host "Full report saved to:"
    Write-Host "  $reportFile"
    Write-Host ""

    Clear-CurrentScenario

    # "Yes" returns to the caller so the interactive menu loop in Main()
    # redraws naturally - no recursion needed. "No" exits.
    $again = Read-Host "Would you like to try another lab? (y/N)"
    if ($again -notmatch "^[yY]$") {
        Write-Host ""
        Write-Host "Training session complete. Great work!"
        Write-Host ""
        Write-Host "To see your overall progress, run:"
        Write-Host "  troubleshootwinlab --report"
        Write-Host ""
        exit 0
    }
}

# ------------------------------------------------------------------
function Show-Help {
    Show-Banner
    Write-Host @"
Usage: troubleshootwinlab [OPTION]

Interactive Docker Desktop troubleshooting training labs (WSL2 backend).

With no options, launches the interactive lab selection menu.

Options:
  --check      Test and grade your current lab solution
  --report     Show your training report card
  --status     Show currently active lab
  --abandon    Abandon current lab without scoring
  --reset      Reset current lab (re-break it)
  --help       Show this help

Lab Workflow:
  1. Run 'troubleshootwinlab' and select a lab
  2. The lab breaks Docker Desktop in a specific way
  3. Diagnose and fix using Docker CLI and Windows tools
  4. Run 'troubleshootwinlab --check' when done
  5. Review your score and feedback
"@
    $current = Get-CurrentScenario
    Write-Host "Current active lab: $(if ($current -and $current -ne 'null') { $current } else { 'None' })"
    Write-Host ""
}

# ------------------------------------------------------------------
function Show-Status {
    Show-Banner
    $current = Get-CurrentScenario
    if (-not $current -or $current -eq "null") {
        Write-Host "No active lab."
        Write-Host ""
        Write-Host "Start a lab with: troubleshootwinlab"
    } else {
        Write-Yellow "Active Lab: $current"
        $startTime = Get-ScenarioStartTime
        $now       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $elapsed   = [int](($now - $startTime) / 60)
        Write-Host "Time elapsed: $elapsed minutes"
        Write-Host ""
        Write-Host "When done, run: troubleshootwinlab --check"
    }
    Write-Host ""
}

# ------------------------------------------------------------------
function Show-ReportCard {
    Show-Banner
    Write-Blue "=========================================="
    Write-Host "Your Training Report Card"
    Write-Blue "=========================================="
    Write-Host ""

    if (-not (Test-Path $GRADES_FILE) -or (Get-Content $GRADES_FILE).Count -le 1) {
        Write-Host "No labs completed yet."
        Write-Host ""
        Write-Host "Start your first lab with: troubleshootwinlab"
        return
    }

    $totalScore = 0
    $labCount   = 0
    $dnsScore   = $null
    $portScore  = $null
    $proxyScore = $null
    $ssoScore   = $null

    # Each scenario variable is overwritten on every matching row, so if a
    # trainee attempted the same lab multiple times only the last score is
    # shown. All attempts count toward the overall average.
    Import-Csv $GRADES_FILE | Where-Object { $_.trainee_id -eq $env:USERNAME } | ForEach-Object {
        switch ($_.scenario) {
            "DNS"   { $dnsScore   = "$($_.score)%" }
            "PORT"  { $portScore  = "$($_.score)%" }
            "PROXY" { $proxyScore = "$($_.score)%" }
            "SSO"   { $ssoScore   = "$($_.score)%" }
        }
        $totalScore += [int]$_.score
        $labCount++
    }

    Write-Host "Lab Scores:"
    Write-Host "  DNS Resolution:  $(if ($dnsScore)   { $dnsScore }   else { 'Not attempted' })"
    Write-Host "  Port Problems:   $(if ($portScore)  { $portScore }  else { 'Not attempted' })"
    Write-Host "  Pull Problems:   $(if ($proxyScore) { $proxyScore } else { 'Not attempted' })"
    Write-Host "  Login Problems:  $(if ($ssoScore)   { $ssoScore }   else { 'Not attempted' })"
    Write-Host ""

    if ($labCount -gt 0) {
        $avg = [int]($totalScore / $labCount)
        Write-Host "Overall Average: $avg%"
        Write-Host ""
        if ($avg -ge 90)    { Write-Green "Grade: A - Excellent!" }
        elseif ($avg -ge 80){ Write-Green "Grade: B - Good work!" }
        elseif ($avg -ge 70){ Write-Yellow "Grade: C - Passing" }
        else                { Write-Red   "Grade: F - Needs improvement" }
    }

    Write-Host ""
    Write-Host "Completed labs: $labCount"
    Write-Host ""
    Write-Blue "=========================================="
    Write-Host ""
}

# ------------------------------------------------------------------
# Invoke-FixCurrentLab - Restore Docker Desktop for the active scenario only.
#
# Called by Abandon-Lab so the environment is clean before the next lab
# starts. Runs the scenario-specific Fix-* function from lib/fix.ps1 rather
# than all.ps1, which avoids unnecessary work on the other scenarios.
#
# Scenarios split into two groups:
#
#   Live fixes (DNS, PORT, BRIDGE) - require a running daemon; use nsenter
#   or docker rm. No Docker Desktop restart is needed.
#
#   Settings fixes (PROXY, PROXYFAIL, SSO, AUTHCONFIG) - write to
#   settings-store.json. Docker Desktop must be stopped first or its graceful-
#   shutdown flush will overwrite the changes. The user is instructed to
#   restart manually before starting a new lab.
# ------------------------------------------------------------------
function Invoke-FixCurrentLab {
    $scenario = Get-CurrentScenario
    if (-not $scenario -or $scenario -eq "null") { return }

    Write-Host ""
    Write-Yellow "Restoring environment for lab: $scenario"
    Write-Host ""

    switch ($scenario) {
        "DNS"   { Fix-Dns;    break }
        "PORT"  { Fix-Ports;  break }
        "BRIDGE"{ Fix-Bridge; break }

        { $_ -in @("PROXY", "PROXYFAIL", "SSO", "AUTHCONFIG") } {
            # These scenarios write to settings-store.json. Docker Desktop must
            # be stopped before the write so the running process cannot flush
            # in-memory state back over our changes on shutdown.
            Stop-DockerDesktop
            Write-Host ""

            switch ($scenario) {
                "PROXY"      { Fix-Proxy;      break }
                "PROXYFAIL"  { Fix-ProxyFail;  break }
                "SSO"        { Fix-Sso;        break }
                "AUTHCONFIG" { Fix-AuthConfig; break }
            }

            Write-Host ""
            Write-Yellow "Docker Desktop was stopped to apply the fix."
            Write-Host "Restart Docker Desktop manually, then start your next lab."
            break
        }

        default {
            Write-Yellow "No targeted fix available for: $scenario"
            Write-Host "Use option 9 (Fix All) to restore the environment manually."
        }
    }

    Write-Host ""
}

# ------------------------------------------------------------------
# Abandon-Lab - Discard the active lab without scoring it.
#
# Applies the scenario-specific fix synchronously before clearing state so
# the environment is clean when the next lab starts.
# ------------------------------------------------------------------
function Abandon-Lab {
    $current = Get-CurrentScenario
    if (-not $current -or $current -eq "null") {
        Write-Host "No active lab to abandon."
        return
    }
    Write-Yellow "Abandoning lab: $current"
    $confirm = Read-Host "Are you sure? This will not be scored. (y/N)"
    if ($confirm -match "^[yY]$") {
        # Fix the environment before clearing state. This runs synchronously
        # so the user can see what is happening and gets the restart prompt
        # for settings-store.json scenarios before the menu redraws.
        Invoke-FixCurrentLab
        Clear-CurrentScenario
        Write-Host "Lab abandoned."
    } else {
        Write-Host "Cancelled."
    }
}

# ------------------------------------------------------------------
function Reset-Lab {
    $current = Get-CurrentScenario
    if (-not $current -or $current -eq "null") {
        Write-Host "No active lab to reset."
        return
    }
    Write-Yellow "Resetting lab: $current"
    Write-Host "This will re-break the environment so you can try again."
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -match "^[yY]$") {
        $breakScript = "$INSTALL_DIR\scenarios\break_$($current.ToLower()).ps1"
        & powershell -ExecutionPolicy Bypass -File $breakScript
        Set-ScenarioStartTime ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Write-Green "Lab reset. Timer restarted. Good luck!"
    } else {
        Write-Host "Cancelled."
    }
}

# ------------------------------------------------------------------
# Main - Entry point
#
# The menu has two distinct states:
#   Active lab:   options to continue, submit, abandon, or view report
#   No active lab: options to start a lab or view report
# Get-CurrentScenario is called once per loop iteration rather than once at
# startup so it picks up state changes made by Check-Lab and Abandon-Lab.
#
# Note on PowerShell switch fall-through: unlike bash case, PowerShell switch
# continues matching after a case runs unless it hits break, return, or exit.
# The --check and --submit cases call Check-Lab (which may return rather than
# exit), so they need an explicit break to prevent the default case from
# also running and printing "Unknown option".
function Main {
    switch ($Action) {
        "--check"   { Check-Lab; break }
        "--submit"  { Check-Lab; break }
        "--help"    { Show-Help;       exit 0 }
        "-h"        { Show-Help;       exit 0 }
        "--status"  { Show-Status;     exit 0 }
        "--report"  { Show-ReportCard; exit 0 }
        "--grades"  { Show-ReportCard; exit 0 }
        "--abandon" { Abandon-Lab;     exit 0 }
        "--reset"   { Reset-Lab;       exit 0 }
        { $_ -ne "" } {
            Write-Host "Unknown option: $Action"
            Write-Host "Run 'troubleshootwinlab --help' for usage information."
            exit 1
        }
    }

    # Interactive loop
    while ($true) {
        Show-MainMenu
        $choice  = Read-Host "Select option"
        $current = Get-CurrentScenario

        if ($current -and $current -ne "null") {
            switch ($choice) {
                "1" { Write-Host ""; Write-Host "Continue working. Run 'troubleshootwinlab --check' when done."; Read-Host "Press enter to continue"; exit 0 }
                "2" { Check-Lab }
                "3" { Abandon-Lab }
                "4" { Show-ReportCard; Read-Host "Press enter to continue" }
                "0" { Write-Host "Goodbye!"; exit 0 }
                default { Write-Host "Invalid option"; Start-Sleep 1 }
            }
        } else {
            switch ($choice) {
                "1" { Start-Lab 1; exit 0 }
                "2" { Start-Lab 2; exit 0 }
                "3" { Start-Lab 3; exit 0 }
                "4" { Start-Lab 4; exit 0 }
                "5" { Show-ReportCard; Read-Host "Press enter to continue" }
                "0" { Write-Host "Goodbye!"; exit 0 }
                default { Write-Host "Invalid option"; Start-Sleep 1 }
            }
        }
    }
}

Main
