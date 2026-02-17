# Changelog

All notable changes to Docker Desktop Training Labs will be documented in this file.

## [1.0.1] - 2025-02-13

### Bug Fixes

#### Critical
- **Added missing test_chaos.sh**: CHAOS MODE (Lab 5) now has proper testing support with comprehensive validation of all four systems
- **Fixed Bash 3 compatibility**: Replaced `${var,,}` syntax in `reset_lab()` and `check_lab()` functions with `tr` command for macOS default Bash 3.2
- **Fixed proxy break script**: Now properly detects shell type (zsh/bash), creates timestamped backups, and provides clear user instructions without dangerous `source` commands

#### Major  
- **Added Python 3 dependency check**: Both `install.sh` and `bootstrap.sh` now verify Python 3.6+ is available before installation
- **Fixed port squatter cleanup**: `break_ports.sh` now kills existing squatter processes and containers before creating new ones, preventing zombie process accumulation
- **Fixed bridge network cleanup**: `break_bridge.sh` now removes existing fake networks before creating new ones, preventing inconsistent state
- **Added state directory initialization**: Main script now creates required directories on startup, preventing failures if installation was interrupted
- **Added safe score parsing**: `check_lab()` function now uses default values (0) for missing test output, preventing arithmetic errors

### Improvements
- More robust error handling throughout
- Better cleanup in all break scripts  
- Timestamped backups for shell RC files
- Clear user messaging about required restarts

## [1.0.0] - 2025-02-12

### Initial Release

First public release of Docker Desktop Training Labs for macOS.

#### Scenarios Added
- **DNS Resolution Failure** - Container networking and DNS troubleshooting
- **Port Binding Conflicts** - Port management and process inspection
- **Bridge Network Corruption** - Docker networking architecture and iptables
- **Proxy Configuration Issues** - Enterprise proxy settings
- **Chaos Mode** - All scenarios combined for advanced practice

#### Features
- Interactive menu-driven CLI interface
- Automatic testing and grading system
- Progress tracking with report cards
- Leaderboard for competitive training
- State persistence (pause/resume labs)
- Color-coded terminal output
- Detailed test reports saved to disk
- Multiple fix validation per scenario

#### Technical Details
- Supports macOS 12+ (Monterey and later)
- Compatible with Docker Desktop 4.x and 5.x
- Uses nsenter for Docker VM manipulation
- Implements realistic break mechanisms from actual support tickets
- Tests validate both fixes and diagnostic methodology

---

## Roadmap

Future versions may include:

### v1.1.0 (Planned)
- Windows-specific scenarios
- Linux desktop scenarios  
- Additional networking labs (DNS over TLS, IPv6)
- Volume mount permission issues
- Extension compatibility problems

### v1.2.0 (Planned)
- Web-based dashboard for instructors
- Team scoring and analytics
- Custom scenario builder
- Integration with Jira for ticket correlation
- Video walkthroughs of solutions

### v2.0.0 (Future)
- Multi-platform unified installer
- Real-time collaboration mode
- AI-powered hints system
- Performance profiling scenarios
- Security hardening exercises

---

## Version History

| Version | Date       | Changes                          |
|---------|------------|----------------------------------|
| 1.0.1   | 2025-02-13 | Bug fixes (Bash 3, CHAOS test, cleanup) |
| 1.0.0   | 2025-02-12 | Initial release with 5 scenarios |

---

## Migration Notes

### From 1.0.0 to 1.0.1

No migration needed. Simply reinstall:

```bash
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/bootstrap.sh | bash
```

Your training data in `~/.docker-training-labs` will be preserved.

### From Pre-Release Versions

If you tested pre-release versions, clean install is recommended:

```bash
# Uninstall old version
sudo rm -rf /usr/local/lib/docker-training-labs
sudo rm /usr/local/bin/troubleshootmaclab

# Remove old data (optional - keeps your scores)
# rm -rf ~/.docker-training-labs

# Install new version
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/bootstrap.sh | bash
```

Your training data in `~/.docker-training-labs` will be preserved if not deleted.
