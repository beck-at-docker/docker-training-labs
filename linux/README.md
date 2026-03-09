# Docker Desktop Training Labs - Linux

Break-fix troubleshooting training for Docker Desktop on Linux.

## What this is

A set of hands-on labs that deliberately corrupt a Docker Desktop for Linux
environment in realistic ways. Trainees diagnose and fix each issue, then
submit their solution for automated grading.

## Requirements

- Docker Desktop for Linux (not plain Docker Engine)
  - https://docs.docker.com/desktop/install/linux-install/
- Python 3.6+
- Bash 4+
- sudo access (installer writes to /usr/local)

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs-linux/main/lab/bootstrap.sh | bash
```

Override branch:

```bash
BRANCH=dev curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash
```

## Usage

```
troubleshootlinuxlab              # Interactive lab menu
troubleshootlinuxlab --check      # Submit current lab for grading
troubleshootlinuxlab --status     # Show active lab and elapsed time
troubleshootlinuxlab --report     # View your report card
troubleshootlinuxlab --abandon    # Abandon current lab without scoring
troubleshootlinuxlab --reset      # Re-break the current lab to try again
troubleshootlinuxlab --help       # Show help
```

## Available labs

| # | Lab | Difficulty | Time |
|---|-----|------------|------|
| 1 | DNS Resolution Failure | ** | 15-20 min |

More labs are planned as the series expands.

## Repository structure

```
lab/
├── bootstrap.sh               # One-command installer (run via curl)
├── install.sh                 # Local installer
├── troubleshootlinuxlab       # Main CLI
├── lib/
│   ├── colors.sh              # Terminal colour definitions
│   ├── state.sh               # JSON state management
│   └── grading.sh             # Grade recording
├── scenarios/
│   └── break_dns.sh           # DNS break script
└── tests/
    ├── test_framework.sh      # Shared test harness
    └── test_dns.sh            # DNS scenario validator
```

## Training data

State files are written to `~/.docker-training-labs/`:

```
~/.docker-training-labs/
├── config.json        # Active lab state
├── grades.csv         # Completed lab scores
└── reports/           # Per-lab test reports
```

## Related repos

- [docker-training-labs](https://github.com/beck-at-docker/docker-training-labs) - macOS
- [docker-training-labs-windows](https://github.com/beck-at-docker/docker-training-labs-windows) - Windows / WSL2
