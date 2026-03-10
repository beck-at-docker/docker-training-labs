# Fix Scripts - Usage Guide

All automated fix scripts have been created in `/Users/beck/labs-dd/mac/fixes/`

## Quick Start

```bash
cd /Users/beck/labs-dd/mac/fixes

# Make executable (first time only)
chmod +x *.sh

# Fix everything
./fix_all.sh
```

---

## Available Fix Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `fix_dns.sh` | Restore DNS resolution | After running break_dns.sh |
| `fix_ports.sh` | Clean up port squatters | After running break_ports.sh |
| `fix_bridge.sh` | Restore bridge network | After running break_bridge.sh |
| `fix_proxy.sh` | Remove proxy config | After running break_proxy.sh |
| `fix_all.sh` | Fix all systems | After running break_all.sh (CHAOS) |
| `setup_fixes.sh` | Make all scripts executable | First time setup |
| `DEV_QUICK_START.sh` | Show quick reference | Quick command reference |

---

## Common Testing Workflows

### Test a Single Lab

```bash
# Break it
cd /Users/beck/labs-dd/mac
sudo bash scenarios/break_dns.sh

# Verify it's broken
docker run --rm alpine:latest nslookup google.com  # Should fail

# Fix it
bash fixes/fix_dns.sh

# Verify the fix
docker run --rm alpine:latest nslookup google.com  # Should work

# Test the test script
bash tests/test_dns.sh fixed  # Should get 100% score
```

### Test CHAOS MODE (All Labs)

```bash
# Break everything
sudo bash scenarios/break_all.sh

# Verify everything is broken (multiple failures expected)

# Fix everything
bash fixes/fix_all.sh

# IMPORTANT: Restart Docker Desktop
# Click whale icon → Restart → Wait

# Test the fix
bash tests/test_chaos.sh fixed  # Should get high score
```

### Test Full CLI Experience

```bash
# Install the system
sudo ./install.sh

# Run the CLI
troubleshootmaclab

# Select a lab (e.g., option 1 for DNS)
# It will run the break script

# Fix it with automation (for testing)
bash fixes/fix_dns.sh

# Or fix manually (for real training)
# ... diagnose and fix yourself ...

# Submit for grading
troubleshootmaclab --check
```

---

## Important Notes

### Restart Requirements

Some fixes require Docker Desktop restart to take full effect:

**Always restart after:**
- `fix_proxy.sh` (daemon.json changes)
- `fix_all.sh` (contains proxy fix)

**Sometimes restart after:**
- `fix_bridge.sh` (if iptables rules don't restore)

**Rarely restart after:**
- `fix_dns.sh` (usually works immediately)
- `fix_ports.sh` (just container cleanup)

### Why Fix Scripts Exist

These are **development tools** for:
1. Testing break scripts work correctly
2. Testing test scripts detect issues
3. Rapid iteration during development
4. Verifying end-to-end workflow
5. Recovering from testing mistakes

**Never give these to trainees** - they should learn to diagnose and fix manually!

---

## File Organization

```
/Users/beck/labs-dd/mac/
├── scenarios/          # Break scripts (distributed to trainees)
│   ├── break_dns.sh
│   ├── break_ports.sh
│   ├── break_bridge.sh
│   ├── break_proxy.sh
│   └── break_all.sh
│
├── fixes/              # Fix scripts (DEV ONLY - not in git)
│   ├── fix_dns.sh
│   ├── fix_ports.sh
│   ├── fix_bridge.sh
│   ├── fix_proxy.sh
│   ├── fix_all.sh
│   ├── setup_fixes.sh
│   ├── DEV_QUICK_START.sh
│   └── README.md
│
└── tests/              # Test scripts (distributed to trainees)
    ├── test_dns.sh
    ├── test_port.sh
    ├── test_bridge.sh
    ├── test_proxy.sh
    └── test_chaos.sh
```

The `fixes/` directory is excluded from git (see .gitignore), so these scripts stay on your development machine only.

---

## Quick Commands

```bash
# See all available commands
cd /Users/beck/labs-dd/mac/fixes
bash DEV_QUICK_START.sh

# Setup (first time)
bash setup_fixes.sh

# Fix everything quickly
bash fix_all.sh
```

---

That's it! You now have automated fix scripts for rapid development testing.
