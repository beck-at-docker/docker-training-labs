# Docker Desktop Training Labs

Interactive break-fix training scenarios for Docker Desktop troubleshooting on macOS.

## 🚀 Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh | bash
```

Or clone and install manually:

```bash
git clone https://github.com/your-org/docker-training-labs.git
cd docker-training-labs
sudo ./install.sh
```

## 📚 What You'll Learn

### Lab 1: DNS Resolution Failure
**Difficulty:** ★★☆☆☆ | **Time:** 15-20 min

Learn container networking and DNS troubleshooting. Fix broken DNS resolution in Docker Desktop containers.

### Lab 2: Port Binding Conflicts
**Difficulty:** ★★☆☆☆ | **Time:** 10-15 min

Master port management and process inspection. Identify and resolve port conflicts preventing container startup.

### Lab 3: Bridge Network Corruption
**Difficulty:** ★★★★☆ | **Time:** 20-30 min

Deep dive into Docker networking architecture and iptables. Restore broken container-to-container and internet connectivity.

### Lab 4: Proxy Configuration Issues
**Difficulty:** ★★★☆☆ | **Time:** 15-25 min

Handle enterprise proxy settings and troubleshooting. Fix misconfigured proxy preventing registry access.

### Lab 5: 💀 CHAOS MODE
**Difficulty:** ★★★★★ | **Time:** 60+ min

All issues at once! Diagnose and fix multiple simultaneous failures in a realistic disaster scenario.

## 🎯 Usage

### Start Training
```bash
troubleshootmaclab
```

Select a lab from the interactive menu and follow the instructions.

### Submit for Grading
When you think you've fixed the issue:
```bash
troubleshootmaclab --check
```

### View Progress
```bash
troubleshootmaclab --report
```

### Other Commands
```bash
troubleshootmaclab --status       # Show active lab
troubleshootmaclab --leaderboard  # See top performers
troubleshootmaclab --reset        # Reset current lab
troubleshootmaclab --abandon      # Abandon current lab
troubleshootmaclab --help         # Show all options
```

## ✅ Requirements

- macOS 12+ (Monterey or later)
- Docker Desktop 4.x+ (must be running)
- Sudo access for installation
- Basic command-line knowledge
- 2GB free disk space

## 🏆 Features

- ✨ Interactive menu-driven interface
- 📊 Automatic testing and scoring
- 📈 Progress tracking and report cards
- 🥇 Leaderboard support
- 💾 State persistence (pause/resume labs)
- 🎨 Color-coded output
- 🔄 Repeatable scenarios

## 📖 Documentation

- [Quick Start Guide](QUICKSTART.md)
- [Installation Options](docs/INSTALL.md)
- [Changelog](CHANGELOG.md)

## 🔧 Uninstall

```bash
sudo rm -rf /usr/local/lib/docker-training-labs
sudo rm /usr/local/bin/troubleshootmaclab
rm -rf ~/.docker-training-labs
```

## 🤝 Support

For issues or questions:
1. Check the documentation in `docs/`
2. Review common issues in troubleshooting guide
3. Contact your TSE training coordinator

## 📝 License

Internal training use only - Not for public distribution.

## 🎓 Learning Path

Recommended order for beginners:
1. DNS Resolution Failure (basics)
2. Port Binding Conflicts (process management)
3. Proxy Configuration (enterprise environment)
4. Bridge Network Corruption (advanced networking)
5. Chaos Mode (test everything)

Each lab builds on concepts from previous ones!

---

**Ready to start?** Run `troubleshootmaclab` and begin your journey to Docker Desktop mastery! 🚀
