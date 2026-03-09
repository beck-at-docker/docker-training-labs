# Docker Desktop Training Labs

Break-fix troubleshooting labs for Docker Desktop across Mac, Linux, and Windows.
Trainees are presented with a broken Docker Desktop environment and must diagnose
and resolve the issue without hints about the nature of the break.

---

## Mac

### Prerequisites

- Docker Desktop installed and running
- macOS (Intel or Apple Silicon)

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/mac/bootstrap.sh | bash
```

### Run

```bash
troubleshootmaclab
```

Training data is stored in `~/.docker-training-labs/`

---

## Linux

### Prerequisites

- Docker Desktop installed and running
- Python 3.6 or later

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/linux/bootstrap.sh | bash
```

### Run

```bash
troubleshootlinuxlab
```

Training data is stored in `~/.docker-training-labs/`

---

## Windows

### Prerequisites

- Docker Desktop installed and running with the WSL2 backend
- PowerShell (elevation is handled automatically)

### Install

```powershell
irm https://raw.githubusercontent.com/beck-at-docker/docker-training-labs/main/windows/bootstrap.ps1 | iex
```

### Run

```powershell
troubleshootwinlab
```

Training data is stored in `%USERPROFILE%\.docker-training-labs\`
