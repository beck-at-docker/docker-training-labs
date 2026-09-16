# break_disk.ps1 - Fills the Docker Desktop WSL2 VM's shared virtual disk to
# simulate "no space left on device" failures.
#
# With the WSL2 backend, every image layer, container writable layer, and
# volume lives inside a single virtual disk - the docker-desktop-data
# distro's ext4.vhdx, under %LOCALAPPDATA%\Docker\wsl\. There is no
# per-volume quota, so if anything on that disk grows large enough, EVERY
# docker operation that needs to write starts failing with ENOSPC, not just
# the container that caused it:
#
#   write /var/lib/docker/...: no space left on device
#
# This scenario creates one oversized file inside a dedicated volume to
# reproduce that failure mode safely and reversibly - deleting the file frees
# the space immediately, with no VM rebuild, WSL shutdown, or vhdx compaction
# required.
#
# The fill size is computed from the VM's actual available space at
# break-time (via 'df' inside a throwaway container) rather than a fixed byte
# count, so this behaves the same way regardless of how large the trainee's
# ext4.vhdx has grown.
#
# IMPORTANT: the fill deliberately stops $reserveKb short of 100% full.
# Docker's own daemon needs to write small amounts of metadata even to delete
# things (container/volume removal records, containerd state, image manifest
# cache). A disk sitting at literally 0 bytes free can make those writes fail
# too, which would mean the trainee's cleanup commands - and Fix-Disk - can no
# longer remove the offending volume, permanently locking the lab in a broken
# state. Reserving a small margin keeps that headroom available while still
# leaving far less than the 100MB test_disk.ps1 checks for, so the training
# symptom is unaffected.
#
# Note: the vhdx does not shrink on its own once it has expanded. Freeing the
# space inside the VM is enough to fix the lab, but the file on the Windows
# host stays large until it is compacted - a real-world detail worth knowing,
# and one the lab brief points trainees at.

Write-Host "Breaking Docker Desktop..."

docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker Desktop is not running"
    exit 1
}

docker rm -f disk-hog 2>&1 | Out-Null
docker volume rm -f disk-hog-volume 2>&1 | Out-Null
docker volume create disk-hog-volume 2>&1 | Out-Null

Write-Host "Checking available space in the Docker Desktop VM..."

# df -k reports 1K blocks; field 4 is the available count. Out-String plus an
# explicit Trim is needed because the docker CLI hands back an object array
# whose elements carry trailing whitespace on Windows.
$dfOutput = docker run --rm -v disk-hog-volume:/data alpine:latest `
    sh -c "df -k /data | tail -1 | awk '{print `$4}'" 2>&1 | Out-String
$availKb = 0
if (-not [int]::TryParse($dfOutput.Trim(), [ref]$availKb)) {
    Write-Host "Error: could not determine available disk space (df returned: '$($dfOutput.Trim())')"
    exit 1
}

if ($availKb -le 0) {
    Write-Host "Error: could not determine available disk space"
    exit 1
}

# Leave a fixed margin of real free space rather than overshooting to a
# guaranteed-full disk (see IMPORTANT note above). 30MB is comfortably more
# than Docker's own metadata writes need, and comfortably less than the 100MB
# test_disk.ps1 requires as proof the fix reclaimed real space.
$reserveKb = 30720
$fillKb    = $availKb - $reserveKb

if ($fillKb -le 0) {
    Write-Host "Error: not enough free space in the Docker Desktop VM to run this scenario safely"
    Write-Host "  (need at least $([int]($reserveKb / 1024))MB free before starting)"
    exit 1
}

$fillMb = [int]($fillKb / 1024)

Write-Host "Filling the Docker Desktop virtual disk (this can take a minute)..."
docker run -d --name disk-hog -v disk-hog-volume:/data alpine:latest `
    sh -c "dd if=/dev/zero of=/data/filler bs=1M count=$fillMb 2>/dev/null; tail -f /dev/null" 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: failed to start the disk-hog container"
    exit 1
}

# Wait for dd to finish writing rather than declaring the environment broken
# while the fill is still in progress. pgrep returns non-zero once dd is gone.
Write-Host "Waiting for the disk to fill..."
for ($i = 0; $i -lt 60; $i++) {
    docker exec disk-hog pgrep dd 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { break }
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Docker Desktop broken"
Write-Host "Symptom: docker pull / docker run / docker build fail with 'no space left on device'"
