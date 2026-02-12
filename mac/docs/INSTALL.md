# Installation Instructions

Multiple ways to install Docker Desktop Training Labs on your Mac.

## Method 1: One-Command Install (Recommended)

The fastest way to get started:

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh | bash
```

This will:
1. ✅ Verify Docker Desktop is running
2. 📥 Download the training labs from GitHub
3. 🔧 Install the `troubleshootmaclab` command
4. ✨ Set up your training environment

**Done!** Run `troubleshootmaclab` to start.

---

## Method 2: Clone from GitHub

If you prefer to see the code first:

```bash
# Clone the repository
git clone https://github.com/your-org/docker-training-labs.git

# Enter the directory
cd docker-training-labs

# Run the installer
sudo ./install.sh
```

---

## Method 3: Download Release Tarball

If you want a specific version:

```bash
# Download latest release
curl -LO https://github.com/your-org/docker-training-labs/releases/latest/download/docker-training-labs.tar.gz

# Extract
tar -xzf docker-training-labs.tar.gz

# Install
cd docker-training-labs
sudo ./install.sh
```

---

## Method 4: Inspect Before Running

For security-conscious users:

```bash
# Download bootstrap script
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh > /tmp/bootstrap.sh

# Review the script
less /tmp/bootstrap.sh

# Run if satisfied
bash /tmp/bootstrap.sh
```

---

## Verify Installation

After installation, verify it worked:

```bash
# Check command exists
which troubleshootmaclab
# Should show: /usr/local/bin/troubleshootmaclab

# View help
troubleshootmaclab --help

# Check status
troubleshootmaclab --status
```

---

## Troubleshooting Installation

### "Command not found" after install

Your shell needs to refresh its PATH cache:

```bash
hash -r
```

Or simply open a new terminal window.

### "Docker Desktop is not running"

Start Docker Desktop:

```bash
open -a Docker
```

Wait for it to fully start (you'll see the whale icon in your menu bar).

### "Permission denied"

The installer requires sudo:

```bash
sudo ./install.sh
```

### Installation fails with "directory exists"

You may have a previous installation. Uninstall first:

```bash
sudo rm -rf /usr/local/lib/docker-training-labs
sudo rm /usr/local/bin/troubleshootmaclab
rm -rf ~/.docker-training-labs
```

Then retry the installation.

---

## What Gets Installed?

The installer creates:

### System Files (requires sudo)
- `/usr/local/lib/docker-training-labs/` - Main program files
  - `troubleshootmaclab` - Main executable
  - `lib/` - Library functions
  - `scenarios/` - Break scripts
  - `tests/` - Testing harnesses
- `/usr/local/bin/troubleshootmaclab` - Symlink for easy access

### User Files (in your home directory)
- `~/.docker-training-labs/` - Your training data
  - `config.json` - Current state
  - `grades.csv` - Your scores
  - `reports/` - Detailed test reports

Total size: ~500KB

---

## Updating

To update to the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh | bash
```

The bootstrap script will update your existing installation.

---

## Uninstalling

To completely remove the training labs:

```bash
# Remove system files
sudo rm -rf /usr/local/lib/docker-training-labs
sudo rm /usr/local/bin/troubleshootmaclab

# Remove your training data (optional)
rm -rf ~/.docker-training-labs
```

**Note:** This will delete all your training scores and progress.

---

## Next Steps

Once installed:

1. Read the [Quick Start Guide](../QUICKSTART.md)
2. Run `troubleshootmaclab` to begin
3. Start with Lab 1 (DNS Resolution)

Happy troubleshooting! 🚀
