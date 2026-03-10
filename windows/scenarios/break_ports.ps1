# scenarios/break_ports.ps1 - Creates port conflicts for common Docker ports
#
# Occupies five ports that trainees are likely to need:
#   80, 443  - nginx containers named 'port-squatter-*' (easy to find with docker ps)
#   3306     - mysql container (slightly harder - requires knowing the port)
#   5432     - postgres container named 'background-db' (generic name blends in
#              with real infrastructure; less obvious than 'squatter-*' names)
#   8080     - .NET TcpListener in a PowerShell background job (not a container;
#              trainees must look beyond 'docker ps' to find and stop it)
#
# Python is not a guaranteed Windows prerequisite, so port 8080 is held by a
# PowerShell background job running a System.Net.Sockets.TcpListener instead.
# The job ID is saved to $env:TEMP\port_squatter_8080_job.txt for cleanup.

Write-Host "Breaking Docker Desktop..."

$jobIdFile = "$env:TEMP\port_squatter_8080_job.txt"

# Clean up any existing squatter containers
$existingContainers = @("port-squatter-80", "port-squatter-443", "port-squatter-3306", "background-db")
foreach ($name in $existingContainers) {
    docker rm -f $name 2>&1 | Out-Null
}

# Stop any existing background job holding port 8080
if (Test-Path $jobIdFile) {
    $oldJobId = Get-Content $jobIdFile -ErrorAction SilentlyContinue
    if ($oldJobId) {
        Stop-Job  -Id $oldJobId -ErrorAction SilentlyContinue
        Remove-Job -Id $oldJobId -ErrorAction SilentlyContinue
    }
    Remove-Item $jobIdFile -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 1

# Start containers that squat on common ports
docker run -d --name port-squatter-80  -p 80:80   nginx:alpine
docker run -d --name port-squatter-443 -p 443:443 nginx:alpine
docker run -d --name port-squatter-3306 -p 3306:3306 `
    -e MYSQL_ROOT_PASSWORD=dummy mysql:8

# Start a .NET TcpListener in a background job to hold port 8080.
# AcceptTcpClient() blocks until a connection arrives; each accepted
# connection is immediately closed so the listener keeps running and
# the port stays bound. This is the Windows equivalent of the Python
# http.server used on Mac and Linux.
$job = Start-Job -ScriptBlock {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, 8080)
    $listener.Start()
    try {
        while ($true) {
            $client = $listener.AcceptTcpClient()
            $client.Close()
        }
    } finally {
        $listener.Stop()
    }
}
$job.Id | Set-Content $jobIdFile
Write-Host "  Background TCP listener started on port 8080 (job $($job.Id))"

# Create a less obvious container on port 5432. The generic name 'background-db'
# blends in with real infrastructure and is harder to spot than 'squatter-*'.
docker run -d --name background-db -p 5432:5432 `
    -e POSTGRES_PASSWORD=dummy postgres:alpine

# Wait for mysql to finish initialising and actually bind port 3306.
Write-Host "Waiting for mysql to bind port 3306..."
$mysqlReady = $false
for ($i = 0; $i -lt 30; $i++) {
    $result = docker exec port-squatter-3306 mysqladmin ping -u root -pdummy --silent 2>&1
    if ($LASTEXITCODE -eq 0) {
        $mysqlReady = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $mysqlReady) {
    Write-Host "Warning: mysql did not become ready within 60s - port 3306 may not be held"
}

Write-Host ""
Write-Host "Docker Desktop broken..."
Write-Host "Symptoms: New containers will fail to bind with 'address already in use'"
