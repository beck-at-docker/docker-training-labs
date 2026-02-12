# Getting Started - Pushing to GitHub

## Quick Commands to Push to GitHub

```bash
# 1. Navigate to the directory
cd /Users/beck/labs-dd/mac

# 2. Initialize git repository
git init

# 3. Add all files
git add .

# 4. Make initial commit
git commit -m "Initial release of Docker Desktop Training Labs

- DNS Resolution Failure scenario
- Port Binding Conflicts scenario
- Bridge Network Corruption scenario
- Proxy Configuration Issues scenario
- Chaos Mode (all labs combined)
- Interactive CLI with grading system
- Progress tracking and leaderboards
- Automated testing harness"

# 5. Create GitHub repository (do this on github.com first!)
# Go to https://github.com/new
# Create a new repository named "docker-training-labs"
# DON'T initialize with README (we already have one)

# 6. Add the remote (replace YOUR-ORG with your GitHub org/username)
git remote add origin https://github.com/YOUR-ORG/docker-training-labs.git

# 7. Push to GitHub
git branch -M main
git push -u origin main

# 8. Create first release tag
git tag -a v1.0.0 -m "Release v1.0.0 - Initial public release"
git push origin v1.0.0
```

## Updating bootstrap.sh

Before pushing, update the `GITHUB_REPO` variable in `bootstrap.sh`:

```bash
# Open bootstrap.sh
vim bootstrap.sh

# Change this line:
GITHUB_REPO="your-org/docker-training-labs"

# To your actual GitHub path:
GITHUB_REPO="docker/docker-training-labs"  # or whatever your org is
```

## After Pushing

Your trainees can install with:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-ORG/docker-training-labs/main/bootstrap.sh | bash
```

## Private Repository

If you want to keep this internal/private:

1. When creating the repo on GitHub, select "Private"
2. Trainees will need GitHub access to your org
3. They'll need to authenticate when cloning

For private repos, they can install with:

```bash
git clone https://github.com/YOUR-ORG/docker-training-labs.git
cd docker-training-labs
sudo ./install.sh
```

## Testing Before Release

Before sharing with trainees:

```bash
# Test on a clean Mac
cd /Users/beck/labs-dd/mac
sudo ./install.sh

# Run a lab
troubleshootmaclab

# Try grading
troubleshootmaclab --check
```

## File Permissions

Make sure scripts are executable:

```bash
chmod +x troubleshootmaclab
chmod +x bootstrap.sh
chmod +x install.sh
chmod +x scenarios/*.sh
chmod +x tests/*.sh
chmod +x lib/*.sh
```

Git will preserve these permissions.

---

You're all set! Follow the steps above to push to GitHub.
