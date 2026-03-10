# Automated Fix Scripts

**FOR DEVELOPMENT/TESTING ONLY - DO NOT SHARE WITH TRAINEES**

These scripts automatically restore Docker Desktop to a working state after running break scripts. Use these for testing and development, not for training.

## Usage

### Make Scripts Executable
```bash
cd /Users/beck/labs-dd/mac/fixes
chmod +x *.sh
```

### Fix Individual Systems

```bash
# Fix DNS only
bash fix_dns.sh

# Fix port conflicts only
bash fix_ports.sh

# Fix bridge network only
bash fix_bridge.sh

# Fix proxy configuration only
bash fix_proxy.sh
```

### Fix Everything at Once

```bash
bash fix_all.sh
```

This runs all fix scripts in the correct order (bridge → DNS → proxy → ports).

---

## What Each Script Does

### fix_dns.sh
- Removes immutable flag from /etc/resolv.conf
- Restores from backup or creates new config with Google DNS (8.8.8.8, 8.8.4.4)
- Verifies DNS resolution works

### fix_ports.sh
- Removes all port squatter containers (port-squatter-*, .hidden-postgres)
- Kills Python HTTP server on port 8080
- Removes PID file
- Verifies ports are available

### fix_bridge.sh
- Removes fake-bridge-1 and fake-bridge-2 networks
- Removes broken-web and broken-app containers
- Removes blocking iptables DROP rule
- Restores Docker FORWARD chain rules
- Verifies internet and DNS connectivity

### fix_proxy.sh
- Restores daemon.json from backup or removes it
- Removes proxy settings from shell RC files (.zshrc, .bash_profile, .bashrc)
- Unsets proxy environment variables in current shell
- Verifies registry access

### fix_all.sh
- Runs all fix scripts in correct dependency order
- Provides comprehensive status output
- Warns about required Docker Desktop restart

---

## Development Workflow

### Typical Testing Loop

```bash
# 1. Break a system
cd /Users/beck/labs-dd/mac
sudo bash scenarios/break_dns.sh

# 2. Test that it's broken
docker run --rm alpine:latest nslookup google.com  # Should fail

# 3. Test the test script
bash tests/test_dns.sh fixed  # Should show failures

# 4. Fix it automatically
bash fixes/fix_dns.sh

# 5. Test that it's fixed
docker run --rm alpine:latest nslookup google.com  # Should work

# 6. Test the test script again
bash tests/test_dns.sh fixed  # Should show passes
```

### Testing CHAOS MODE

```bash
# Break everything
sudo bash scenarios/break_all.sh

# Fix everything
bash fixes/fix_all.sh

# Restart Docker Desktop (required!)
# Then test
bash tests/test_chaos.sh fixed
```

---

## When to Use

**Use fix scripts for:**
- Testing break scripts work correctly
- Testing test scripts detect issues properly
- Rapid iteration during development
- Recovering from testing mishaps
- Verifying end-to-end workflow

**DON'T use fix scripts for:**
- Training sessions (defeats the purpose)
- Sharing with trainees (they should learn to fix manually)
- Production environments

---

## Notes

### Proxy Fix Requires Restart
The proxy fix cleans up configuration files, but Docker Desktop must be restarted to apply daemon.json changes.

### Bridge Fix May Need Restart
If iptables rules don't restore properly, Docker Desktop restart will regenerate them automatically.

### State Management
Fix scripts do NOT clear the training lab state (active scenario, timer, etc). To clear training state:

```bash
troubleshootmaclab --abandon
# Or manually:
rm -rf ~/.docker-training-labs
```

### Backup Files
Fix scripts restore from the most recent backup when available. Backup files accumulate over time:
- daemon.json.backup-TIMESTAMP
- .zshrc.backup-TIMESTAMP

Clean up old backups periodically if needed.

---

## Troubleshooting Fix Scripts

### "Docker daemon not responding"
Restart Docker Desktop and try again.

### "iptables rules won't restore"
Restart Docker Desktop - it will auto-regenerate default rules.

### "Ports still in use after fix"
Some process outside the training system may be using the port:
```bash
lsof -nP -iTCP:8080 | grep LISTEN
```

### "Fix script doesn't work"
Make sure it's executable:
```bash
chmod +x fixes/fix_*.sh
```
