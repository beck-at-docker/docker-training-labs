#!/bin/bash
# push_to_github.sh - Script to commit and push all bug fixes

set -e

echo "=========================================="
echo "Pushing Bug Fixes to GitHub"
echo "=========================================="
echo ""

# Navigate to the repository
cd /Users/beck/labs-dd/mac

# Check current status
echo "Current git status:"
git status
echo ""

# Check if remote exists
echo "Checking git remote..."
if git remote -v | grep -q origin; then
    echo "✅ Remote 'origin' is configured:"
    git remote -v
else
    echo "❌ No remote configured. Please add one first:"
    echo "   git remote add origin https://github.com/beck-at-docker/docker-training-labs.git"
    echo ""
    read -p "Do you want to add the remote now? (y/N): " add_remote
    if [ "$add_remote" = "y" ] || [ "$add_remote" = "Y" ]; then
        read -p "Enter GitHub repository URL: " repo_url
        git remote add origin "$repo_url"
        echo "✅ Remote added"
    else
        echo "Cancelled. Add remote manually and run this script again."
        exit 1
    fi
fi

echo ""
read -p "Ready to commit and push? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

# Stage all changes
echo ""
echo "Staging changes..."
git add .

# Show what will be committed
echo ""
echo "Files to be committed:"
git status --short
echo ""

# Commit with detailed message
echo "Creating commit..."
git commit -m "Bug fixes: Bash 3 compatibility, CHAOS test, cleanup improvements

Critical fixes:
- Added missing test_chaos.sh for Lab 5 (CHAOS MODE)
- Fixed Bash 3 compatibility in reset_lab() and check_lab()
- Fixed proxy break script shell detection and backup handling

Major fixes:
- Added Python 3 dependency checks in install.sh and bootstrap.sh
- Fixed port squatter cleanup to prevent zombie processes
- Fixed bridge network cleanup to prevent conflicting state
- Added safe score parsing with default values
- Added state directory self-initialization for interrupted installs
- Fixed leaderboard to use awk instead of Bash 4 associative arrays

All fixes verified with simulations. Full Bash 3.2 compatibility confirmed.

Files modified: 7
New files: 3 (test_chaos.sh, BUG_FIXES.md, VERIFICATION_REPORT.md)
Bugs fixed: 9 (3 critical, 5 major, 1 bonus)"

echo "✅ Commit created"
echo ""

# Push to remote
echo "Pushing to origin main..."
git push origin main

echo ""
echo "✅ Successfully pushed to GitHub!"
echo ""

# Offer to create release tag
read -p "Create release tag v1.0.1? (y/N): " create_tag
if [ "$create_tag" = "y" ] || [ "$create_tag" = "Y" ]; then
    git tag -a v1.0.1 -m "Bug fix release v1.0.1

- Bash 3.2 compatibility
- CHAOS MODE testing support
- Improved cleanup and stability
- Self-healing state management"
    
    git push origin v1.0.1
    echo "✅ Tag v1.0.1 created and pushed"
fi

echo ""
echo "=========================================="
echo "Push Complete!"
echo "=========================================="
echo ""
echo "Your changes are now on GitHub."
echo ""
echo "View your repository:"
git remote get-url origin | sed 's/\.git$//'
echo ""
