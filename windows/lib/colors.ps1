# colors.ps1 - Console color output helpers
#
# Thin wrappers around Write-Host -ForegroundColor so callers don't need
# to specify the color parameter inline every time.
# Cyan is used for Blue because PowerShell's 'Blue' is very dark on most
# terminals and hard to read against a black background.

function Write-Blue   { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Green  { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Yellow { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Red    { param($msg) Write-Host $msg -ForegroundColor Red }
