# Quick Git Push Guide

## Automated Push (Recommended)

I've created a helper script for you:

```bash
cd /Users/beck/labs-dd/mac
chmod +x push_to_github.sh
./push_to_github.sh
```

This script will:
1. Check git status
2. Verify remote is configured
3. Stage all changes
4. Create detailed commit message
5. Push to origin main
6. Optionally create v1.0.1 release tag

---

## Manual Commands (If You Prefer)

```bash
cd /Users/beck/labs-dd/mac

# Check status
git status

# Check remote (should show beck-at-docker/docker-training-labs)
git remote -v

# If no remote, add it:
# git remote add origin https://github.com/beck-at-docker/docker-training-labs.git

# Stage all changes
git add .

# Commit
git commit -m "Bug fixes: Bash 3 compatibility, CHAOS test, cleanup improvements

Critical fixes:
- Added missing test_chaos.sh for Lab 5
- Fixed Bash 3 compatibility (tr instead of ${var,,})
- Fixed proxy break script shell detection

Major fixes:
- Added Python 3 dependency checks
- Fixed port squatter cleanup (prevents zombies)
- Fixed bridge network cleanup
- Added safe score parsing with defaults
- Added state directory self-initialization
- Fixed leaderboard Bash 3 compatibility (awk instead of associative arrays)

Bugs fixed: 9 total
All changes verified and tested"

# Push
git push origin main

# Create release tag (optional)
git tag -a v1.0.1 -m "Bug fix release - Bash 3 compatibility"
git push origin v1.0.1
```

---

## Files That Will Be Committed

**New Files:**
- tests/test_chaos.sh
- BUG_FIXES.md
- VERIFICATION_REPORT.md
- push_to_github.sh
- GIT_PUSH_GUIDE.md (this file)

**Modified Files:**
- troubleshootmaclab
- scenarios/break_ports.sh
- scenarios/break_bridge.sh
- scenarios/break_proxy.sh
- install.sh
- bootstrap.sh
- CHANGELOG.md

**Not Committed (per .gitignore):**
- .DS_Store files
- *.backup files
- test_results/
- .docker-training-labs/

---

## Before Pushing

Consider updating placeholder URLs in:
- README.md (line ~8: bootstrap URL)
- QUICKSTART.md (line ~8: bootstrap URL)
- docs/INSTALL.md (multiple locations)
- bootstrap.sh (line ~6: GITHUB_REPO variable)

Current placeholder: `your-org/docker-training-labs`
Your actual repo: `beck-at-docker/docker-training-labs`

Search and replace:
```bash
cd /Users/beck/labs-dd/mac
grep -r "your-org" . --exclude-dir=.git
```

Then update as needed.

---

## After Pushing

Test the installation from GitHub:
```bash
# In a test directory or another Mac
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/bootstrap.sh | bash
```
