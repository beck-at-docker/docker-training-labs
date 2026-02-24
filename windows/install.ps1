# install.ps1 - Install Docker Desktop Training Labs (Windows / WSL2)

$ErrorActionPreference = "Stop"

$INSTALL_DIR = "$env:ProgramData\docker-training-labs"
$STATE_DIR   = "$env:USERPROFILE\.docker-training-labs"
$GRADES_FILE = "$STATE_DIR\grades.csv"

Write-Host "=========================================="
Write-Host "Docker Desktop Training Labs Installer"
Write-Host "=========================================="
Write-Host ""

# Prerequisites
Write-Host "Checking prerequisites..."

try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "  Docker Desktop is running"
} catch {
    Write-Host "ERROR: Docker Desktop is not running. Please start it first."
    exit 1
}

# Confirm WSL2 backend
$dockerInfo = docker info 2>&1 | Out-String
if ($dockerInfo -notmatch "WSL") {
    Write-Host ""
    Write-Host "WARNING: This lab suite targets the WSL2 backend."
    Write-Host "         Your Docker Desktop may be configured for Hyper-V."
    Write-Host "         Some break scenarios may behave differently."
    Write-Host ""
    $confirm = Read-Host "Continue anyway? (y/N)"
    if ($confirm -notmatch "^[yY]$") { exit 0 }
}

# Confirm running as admin (needed to write to ProgramData)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "ERROR: This installer must be run as Administrator."
    Write-Host "       Right-click PowerShell and select 'Run as Administrator'."
    exit 1
}

# Create directories
Write-Host ""
Write-Host "Creating installation directories..."
@(
    $INSTALL_DIR,
    "$INSTALL_DIR\lib",
    "$INSTALL_DIR\scenarios",
    "$INSTALL_DIR\tests",
    $STATE_DIR,
    "$STATE_DIR\reports"
) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}
Write-Host "  Directories created"

# Copy files
Write-Host "Installing training lab files..."
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Copy-Item "$SCRIPT_DIR\troubleshootwinlab.ps1" "$INSTALL_DIR\" -Force
Copy-Item "$SCRIPT_DIR\lib\*.ps1"              "$INSTALL_DIR\lib\" -Force
Copy-Item "$SCRIPT_DIR\scenarios\*.ps1"        "$INSTALL_DIR\scenarios\" -Force
Copy-Item "$SCRIPT_DIR\tests\*.ps1"            "$INSTALL_DIR\tests\" -Force
Write-Host "  Files installed to $INSTALL_DIR"

# Create a cmd shim so 'troubleshootwinlab' works from any prompt
$shimPath = "$env:SystemRoot\System32\troubleshootwinlab.cmd"
@"
@echo off
powershell -ExecutionPolicy Bypass -File "$INSTALL_DIR\troubleshootwinlab.ps1" %*
"@ | Set-Content $shimPath -Encoding ASCII
Write-Host "  Command shim created: troubleshootwinlab"

# Initialise state
Write-Host "Initialising training environment..."
@{
    version             = "1.0.0"
    install_date        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    trainee_id          = $env:USERNAME
    current_scenario    = $null
    scenario_start_time = $null
} | ConvertTo-Json | Set-Content "$STATE_DIR\config.json"

if (-not (Test-Path $GRADES_FILE)) {
    "trainee_id,scenario,score,timestamp,duration_seconds" | Set-Content $GRADES_FILE
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Installation Complete!"
Write-Host "=========================================="
Write-Host ""
Write-Host "To start training, open a new command prompt and run:"
Write-Host "  troubleshootwinlab"
Write-Host ""
Write-Host "Your training data is stored in:"
Write-Host "  $STATE_DIR"
Write-Host ""
