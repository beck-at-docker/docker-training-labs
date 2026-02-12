# Changelog

All notable changes to Docker Desktop Training Labs will be documented in this file.

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
| 1.0.0   | 2025-02-12 | Initial release with 5 scenarios |

---

## Migration Notes

### From Pre-Release Versions

If you tested pre-release versions, clean install is recommended:

```bash
# Uninstall old version
sudo rm -rf /usr/local/lib/docker-training-labs
sudo rm /usr/local/bin/troubleshootmaclab

# Remove old data (optional - keeps your scores)
# rm -rf ~/.docker-training-labs

# Install new version
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh | bash
```

Your training data in `~/.docker-training-labs` will be preserved if not deleted.
