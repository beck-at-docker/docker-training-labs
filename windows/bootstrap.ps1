# bootstrap.ps1 - One-command installer for Docker Desktop Training Labs (Windows)
#
# Usage (run from any PowerShell window - elevation is handled automatically):
#   $env:GH_TOKEN = gh auth token
#   irm "https://raw.githubusercontent.com/docker/docker-training-labs/main/windows/bootstrap.ps1" `
#     -Headers @{ Authorization = "Bearer $env:GH_TOKEN" } | iex
#
# Override branch:
#   $env:BRANCH = "dev"; <above command>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$GITHUB_REPO = "docker/docker-training-labs"
$BRANCH      = if ($env:BRANCH)   { $env:BRANCH }   else { "main" }
$GH_TOKEN    = if ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }

Write-Host ""
Write-Host "=========================================="
Write-Host "Docker Desktop Training Labs Installer"
Write-Host "=========================================="
Write-Host ""

# ------------------------------------------------------------------
# Require a GitHub token — the repo is private.
# ------------------------------------------------------------------
if (-not $GH_TOKEN) {
    Write-Host "ERROR: GH_TOKEN is not set."
    Write-Host ""
    Write-Host "Run:"
    Write-Host '  $env:GH_TOKEN = gh auth token'
    Write-Host '  irm "https://raw.githubusercontent.com/docker/docker-training-labs/main/windows/bootstrap.ps1" `'
    Write-Host '    -Headers @{ Authorization = "Bearer $env:GH_TOKEN" } | iex'
    Write-Host ""
    pause; exit 1
}

# ------------------------------------------------------------------
# Self-elevate if not running as Administrator
#
# install.ps1 writes to $env:ProgramData and $env:SystemRoot\System32,
# both of which require elevation. Bootstrap re-launches itself elevated
# via Start-Process -Verb RunAs, which triggers the UAC prompt.
# $env:BRANCH and $env:GH_TOKEN are forwarded so they survive the
# elevation boundary.
# ------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "Administrator privileges required."
    Write-Host "Re-launching in an elevated window..."
    Write-Host ""
    $scriptUrl    = "https://raw.githubusercontent.com/$GITHUB_REPO/refs/heads/$BRANCH/windows/bootstrap.ps1"
    $authHeader   = "Bearer $GH_TOKEN"
    $elevatedCmd  = "& { `$env:BRANCH='$BRANCH'; `$env:GH_TOKEN='$GH_TOKEN'; " +
                    "`$h=@{Authorization='$authHeader'}; irm '$scriptUrl' -Headers `$h | iex }"
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy", "Bypass", "-Command", $elevatedCmd -Wait
    exit 0
}

# ------------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------------
Write-Host "Checking prerequisites..."

try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    Write-Host "  [OK] Docker Desktop is running"
} catch {
    Write-Host ""
    Write-Host "ERROR: Docker Desktop is not running (or not installed)."
    Write-Host "       Install and start Docker Desktop, then re-run this installer."
    Write-Host "       https://www.docker.com/products/docker-desktop"
    Write-Host ""
    pause; exit 1
}

$psVer = $PSVersionTable.PSVersion
Write-Host "  [OK] PowerShell $($psVer.Major).$($psVer.Minor)"

if ($psVer.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or later is required."
    pause; exit 1
}

Write-Host ""

# ------------------------------------------------------------------
# Download repo ZIP
# ------------------------------------------------------------------
$tempDir  = Join-Path $env:TEMP "docker-training-labs-$(Get-Random)"
$zipPath  = Join-Path $tempDir "labs.zip"
$unzipDir = Join-Path $tempDir "extracted"
$ZIP_URL  = "https://github.com/$GITHUB_REPO/archive/refs/heads/$BRANCH.zip"

New-Item -ItemType Directory -Force -Path $tempDir  | Out-Null
New-Item -ItemType Directory -Force -Path $unzipDir | Out-Null

Write-Host "Downloading training labs from GitHub..."
Write-Host "  Branch : $BRANCH"
Write-Host "  Source : $ZIP_URL"
Write-Host ""

try {
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $ZIP_URL -OutFile $zipPath -UseBasicParsing `
        -Headers @{ Authorization = "Bearer $GH_TOKEN" }
    $ProgressPreference = "Continue"
    Write-Host "  [OK] Download complete"
} catch {
    Write-Host "ERROR: Download failed: $_"
    Write-Host "       Verify your GH_TOKEN has read access to $GITHUB_REPO."
    pause; exit 1
}

Write-Host "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $unzipDir -Force

# GitHub ZIP root is: docker-training-labs-<branch>/
$repoRoot = Get-ChildItem -Directory $unzipDir | Select-Object -First 1
if (-not $repoRoot) {
    Write-Host "ERROR: Unexpected archive structure."
    pause; exit 1
}

# windows lab files live under windows/ within the repo root
$labDir = Join-Path $repoRoot.FullName "windows"
$installScript = Join-Path $labDir "install.ps1"
if (-not (Test-Path $installScript)) {
    Write-Host "ERROR: install.ps1 not found. Expected: $installScript"
    pause; exit 1
}

Write-Host "  [OK] Extraction complete"
Write-Host ""

# ------------------------------------------------------------------
# Run installer
# ------------------------------------------------------------------
Write-Host "Running installer..."
Write-Host ""
& $installScript

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Cleaning up temporary files..."
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=========================================="
Write-Host "Bootstrap complete."
Write-Host "Open a new command prompt and run:"
Write-Host "  troubleshootwinlab"
Write-Host "=========================================="
Write-Host ""
pause
