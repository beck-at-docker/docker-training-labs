#!/bin/bash
# DEV_QUICK_START.sh - Quick reference for development testing
# Run this to see all available commands

cat << 'EOF'
========================================
Docker Training Labs - Development Guide
========================================

SETUP (First Time)
------------------
cd /Users/beck/labs-dd/mac/fixes
chmod +x setup_fixes.sh
./setup_fixes.sh


TESTING WORKFLOW
----------------

# Test Individual Lab:
sudo bash ../scenarios/break_dns.sh      # Break it
docker run --rm alpine:latest nslookup google.com  # Verify broken
bash fix_dns.sh                          # Fix it
bash ../tests/test_dns.sh fixed         # Test the fix


# Test CHAOS MODE:
sudo bash ../scenarios/break_all.sh      # Break everything
bash fix_all.sh                          # Fix everything
# RESTART DOCKER DESKTOP (required!)
bash ../tests/test_chaos.sh fixed       # Test the fix


# Test Full CLI:
sudo ../install.sh                       # Install system
troubleshootmaclab                       # Run CLI
# Select a lab, fix it manually
troubleshootmaclab --check               # Submit for grading


QUICK FIXES
-----------
bash fix_dns.sh         # Fix DNS only
bash fix_ports.sh       # Fix ports only  
bash fix_bridge.sh      # Fix bridge only
bash fix_proxy.sh       # Fix proxy only
bash fix_all.sh         # Fix everything


COMMON COMMANDS
---------------
# Break something:
sudo bash ../scenarios/break_dns.sh
sudo bash ../scenarios/break_ports.sh
sudo bash ../scenarios/break_bridge.sh
sudo bash ../scenarios/break_proxy.sh
sudo bash ../scenarios/break_all.sh

# Fix it:
bash fix_dns.sh
bash fix_ports.sh
bash fix_bridge.sh
bash fix_proxy.sh
bash fix_all.sh

# Test it:
bash ../tests/test_dns.sh fixed
bash ../tests/test_port.sh fixed
bash ../tests/test_bridge.sh fixed
bash ../tests/test_proxy.sh fixed
bash ../tests/test_chaos.sh fixed

# Full system test:
troubleshootmaclab --check


VERIFICATION COMMANDS
---------------------
# Check DNS:
docker run --rm alpine:latest nslookup google.com

# Check ports:
docker run -p 8080:80 nginx:alpine
docker rm -f <container>

# Check bridge:
docker run --rm alpine:latest ping -c 2 8.8.8.8
docker run --rm alpine:latest ping -c 2 google.com

# Check proxy:
docker pull hello-world


RESET TRAINING STATE
--------------------
troubleshootmaclab --abandon             # Abandon current lab
rm -rf ~/.docker-training-labs           # Clear all training data


RESTART DOCKER DESKTOP
----------------------
After proxy or bridge fixes, restart is often needed:
1. Click Docker whale icon in menu bar
2. Select "Restart"
3. Wait for it to fully start


GIT WORKFLOW
------------
# After making changes:
git add .
git commit -m "Your changes"
git push origin main

# Use the automated script:
chmod +x ../push_to_github.sh
../push_to_github.sh


DOCUMENTATION
-------------
README.md              - Main documentation
fixes/README.md        - Fix scripts documentation
BUG_FIXES.md          - Bug fix details
VERIFICATION_REPORT.md - Fix verification results
GIT_PUSH_GUIDE.md     - Git push instructions

========================================
EOF
