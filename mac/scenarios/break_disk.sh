#!/bin/bash
# break_disk.sh - Fills the Docker Desktop VM's shared virtual disk to
# simulate "no space left on device" failures.
#
# Docker Desktop's Linux VM backs every image layer, container writable
# layer, and volume with a single virtual disk (Docker.raw / the VM's data
# volume). There is no per-volume quota - if anything on that disk grows
# large enough, EVERY docker operation that needs to write starts failing
# with ENOSPC, not just the container that caused it:
#
#   write /var/lib/docker/...: no space left on device
#
# This scenario creates one oversized file inside a dedicated volume to
# reproduce that failure mode safely and reversibly - deleting the file
# frees the space immediately, with no VM rebuild or restart required.
#
# The fill size is computed from the VM's actual available space at
# break-time (via `df` inside a throwaway container) rather than a fixed
# byte count, so this works the same way regardless of how large the
# trainee's Docker Desktop disk image is configured to be.
#
# IMPORTANT: the fill deliberately stops RESERVE_KB short of 100% full.
# Docker's own daemon needs to write small amounts of metadata even to
# delete things (container/volume removal records, containerd state,
# image manifest cache, etc). A disk sitting at literally 0 bytes free can
# make those writes fail too, which would mean the trainee's cleanup
# commands - and fix_disk() - can no longer remove the offending volume,
# permanently locking the lab in a broken state. Reserving a small margin
# keeps that headroom available while still leaving far less than the
# 100MB test_disk.sh checks for, so the training symptom is unaffected.

set -e

echo "Breaking Docker Desktop..."

if ! docker info &>/dev/null; then
    echo "Error: Docker Desktop is not running"
    exit 1
fi

docker rm -f disk-hog 2>/dev/null || true
docker volume rm -f disk-hog-volume 2>/dev/null || true
docker volume create disk-hog-volume > /dev/null

echo "Checking available space in the Docker Desktop VM..."
AVAIL_KB=$(docker run --rm -v disk-hog-volume:/data alpine:latest \
    df -k /data | tail -1 | awk '{print $4}')

if [ -z "$AVAIL_KB" ] || [ "$AVAIL_KB" -le 0 ]; then
    echo "Error: could not determine available disk space"
    exit 1
fi

# Leave a fixed margin of real free space rather than overshooting to a
# guaranteed-full disk (see IMPORTANT note above). 30MB is comfortably more
# than Docker's own metadata writes need, and comfortably less than the
# 100MB test_disk.sh requires as proof the fix reclaimed real space.
RESERVE_KB=30720
FILL_KB=$(( AVAIL_KB - RESERVE_KB ))

if [ "$FILL_KB" -le 0 ]; then
    echo "Error: not enough free space in the Docker Desktop VM to run this scenario safely"
    echo "  (need at least $((RESERVE_KB / 1024))MB free before starting)"
    exit 1
fi

FILL_MB=$(( FILL_KB / 1024 ))

echo "Filling the Docker Desktop virtual disk (this can take a minute)..."
docker run -d --name disk-hog -v disk-hog-volume:/data alpine:latest \
    sh -c "dd if=/dev/zero of=/data/filler bs=1M count=$FILL_MB 2>/dev/null; tail -f /dev/null"

# Wait for dd to finish writing rather than declaring the environment
# broken while the fill is still in progress.
echo "Waiting for the disk to fill..."
for i in $(seq 1 60); do
    if ! docker exec disk-hog pgrep dd > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

echo ""
echo "Docker Desktop broken"
echo "Symptoms: docker pull / docker run / docker build all fail with 'no space left on device'"
