# Quick Start Guide

Get up and running with Docker Desktop Training Labs in 5 minutes!

## Step 1: Install

### One-Command Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/your-org/docker-training-labs/main/bootstrap.sh | bash
```

### Or Manual Install
```bash
git clone https://github.com/your-org/docker-training-labs.git
cd docker-training-labs
sudo ./install.sh
```

## Step 2: Verify Installation

```bash
troubleshootmaclab --help
```

You should see the help menu with all available options.

## Step 3: Start Your First Lab

```bash
troubleshootmaclab
```

**Recommended first lab:** DNS Resolution Failure (Option 1)
- Easy difficulty
- 15-20 minutes
- Teaches fundamental Docker Desktop concepts

## Step 4: Troubleshoot!

The lab will break your Docker Desktop in a specific way. Your job:

1. **Observe the symptoms** - What's broken?
2. **Diagnose the root cause** - Use Docker commands
3. **Fix the issue** - Apply your knowledge
4. **Verify the fix** - Test that it works

### Helpful Commands

```bash
# Check Docker status
docker info

# Test container connectivity
docker run --rm alpine:latest ping -c 3 google.com

# Inspect networks
docker network ls
docker network inspect bridge

# Check DNS
docker run --rm alpine:latest cat /etc/resolv.conf

# View container logs
docker logs <container-name>

# Check ports
lsof -nP -iTCP:80 | grep LISTEN
```

## Step 5: Submit for Grading

When you think you've fixed it:

```bash
troubleshootmaclab --check
```

The system will:
- Run automated tests
- Calculate your score
- Provide detailed feedback
- Save a report to your training folder

## Step 6: Track Your Progress

```bash
# View your report card
troubleshootmaclab --report

# See the leaderboard
troubleshootmaclab --leaderboard
```

## Tips for Success

### 🎯 Systematic Approach
1. Document symptoms before diagnosing
2. Form hypotheses about root causes
3. Test each hypothesis systematically
4. Verify fixes thoroughly

### 🔍 Use the Right Tools
- `docker info` - Overall Docker status
- `docker ps -a` - All containers
- `docker network ls` - Networks
- `lsof` - Port usage
- `docker logs` - Container output

### 💡 When Stuck
- Re-read the lab instructions
- Check the diagnostic commands suggested
- Try `troubleshootmaclab --help` for hints
- Reset the lab with `troubleshootmaclab --reset`

### ⚠️ Common Mistakes
- Not checking if Docker Desktop is running
- Skipping systematic diagnostics
- Fixing symptoms instead of root causes
- Not testing the fix thoroughly

## Troubleshooting the Training Tool

### Command Not Found
```bash
# Refresh your shell
hash -r

# Or open a new terminal window
```

### Lab Won't Break
```bash
# Ensure Docker Desktop is running
docker info

# Check you have sudo permissions
sudo echo "test"
```

### Want to Start Over?
```bash
# Abandon current lab
troubleshootmaclab --abandon

# Or reset to try again
troubleshootmaclab --reset
```

## Next Steps

After completing your first lab:

1. **Try the other scenarios** - Each teaches different skills
2. **Improve your score** - Replay labs for mastery
3. **Challenge yourself** - Attempt Chaos Mode!
4. **Compare progress** - Check the leaderboard

## Need Help?

- View this guide: `cat ~/path/to/QUICKSTART.md`
- Full docs: `cat ~/path/to/README.md`
- Help menu: `troubleshootmaclab --help`
- Current status: `troubleshootmaclab --status`

---

**You're all set!** Run `troubleshootmaclab` to begin. Good luck! 🚀
