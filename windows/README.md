# Docker Desktop Training Labs - Windows (WSL2)

## Prerequisites

- Windows 10/11 with WSL2 enabled
- Docker Desktop installed and running with the WSL2 backend
- PowerShell 5.1 or later (included with Windows 10/11)

## Installation

Open PowerShell (elevation is handled automatically) and run:

```powershell
irm https://raw.githubusercontent.com/beck-at-docker/docker-training-labs-windows/main/lab/bootstrap.ps1 | iex
```

Then open a new command prompt and run:

```
troubleshootwinlab
```

## Available Labs

| # | Scenario | Difficulty | Time |
|---|----------|------------|------|
| 1 | DNS Resolution Failure | Medium | 15-20 min |

## Lab Workflow

1. Run `troubleshootwinlab` and select a lab
2. Docker Desktop will be broken in a specific way
3. Use the Docker CLI and Windows tools to diagnose and fix
4. Run `troubleshootwinlab --check` when you think you've fixed it
5. Review your score and feedback

## Commands

```
troubleshootwinlab              # Interactive menu
troubleshootwinlab --check      # Grade your current fix
troubleshootwinlab --status     # Show active lab
troubleshootwinlab --report     # View your scores
troubleshootwinlab --abandon    # Abandon current lab
troubleshootwinlab --reset      # Re-break current lab
troubleshootwinlab --help       # Show help
```

## How the DNS Break Works

The break script runs iptables rules inside the Docker Desktop
WSL2 VM (via a privileged container + nsenter) to drop all
traffic on port 53. This mirrors a real class of networking
issues where DNS fails at the network layer rather than through
configuration files.

The host Windows machine is unaffected. Only container DNS
resolution fails.

Note: iptables rules are ephemeral in the WSL2 VM. Restarting
Docker Desktop will clear the break. If that happens during a
lab, use `troubleshootwinlab --reset` to re-apply it.

## Training Data

Scores and reports are stored in:
```
%USERPROFILE%\.docker-training-labs\
```
