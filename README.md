# Kali VMware Pentest Workflow Setup

This repository contains a post-installation script designed to prepare a Kali Linux VMware environment for penetration testing workflows. It focuses on structure, logging, and efficiency while keeping the default Kali setup intact.

The script is intended to be used alongside the official Kali VMware image and can be combined with tools like PimpMyKali for additional system customization.

---

## Features

### Centralized Workspace (VMware Shared Folder)
- Uses a mounted VMware shared folder (`/mnt/hgfs/...`) as the base directory
- Falls back to the user home directory if no shared folder is detected
- Keeps all pentest data in a location suitable for backups
- Supports interactive setup prompts with default values

### Structured Pentest Workspace

```
pentest-data/
├── assessments/
├── tmux-logs/
├── tools/
├── wordlists/
├── notes/
├── vpn/
├── loot/
└── screenshots/
```

Each assessment gets its own workspace:

```
assessments/<client>/<date>/
├── notes/
├── loot/
├── scans/
├── screenshots/
├── logs/
├── recon/
├── web/
├── infra/
├── evidence/
└── reporting/
```

---

### Tmux Logging (Full Activity Tracking)
- Installs and configures:
  - tmux-logging
  - tmux-resurrect
  - tmux-sessionist
- Sets a high scrollback buffer (50000 lines)
- Stores logs in a centralized directory
- Enables full command and output tracking for reporting and auditing

---

### Assessment Helper Command

Start a new engagement quickly:

```
assess <client-name>
```

This will:
- Create a structured workspace
- Generate basic note templates
- Launch a pre-configured tmux session
- Split panes for parallel workflows

---

### Tooling Setup

Installs commonly used tools via APT:
- Recon: amass, subfinder, assetfinder
- Web: ffuf, gobuster, feroxbuster, nuclei
- Exploitation: sqlmap, netexec, evil-winrm
- Utilities: jq, tmux, git, python3, etc.

Also includes:
- pipx tools (e.g. impacket)
- Go tools (optional)
- Git repositories:
  - PEASS-ng
  - nuclei-templates
  - SecLists (git version)

---

### Wordlists

- Links `/usr/share/seclists` into the workspace
- Keeps all testing resources centralized

### Desktop Behavior

- Can disable screen standby and screen locking
- Useful for long-running scans, captures, and tmux sessions inside a VM

---

## Requirements

- Kali Linux (VMware image recommended)
- VMware Shared Folders enabled (optional but recommended)
- sudo access

---

## Installation

### Interactive local run

```
chmod +x setup-kali-vmware-workflow.sh
sudo ./setup-kali-vmware-workflow.sh
```

### Interactive remote run

```
curl -fsSL https://example.com/setup-kali-vmware-workflow.sh | sudo bash
```

The script prompts for configuration values and shows defaults that can be accepted by pressing Enter.

### Override values non-interactively

```
curl -fsSL https://example.com/setup-kali-vmware-workflow.sh | sudo SHARE_NAME=Shared BASE_SUBDIR=pentest-data ENABLE_SSH=false bash
```

---

## After Installation

### Start tmux

```
tmux new -s setup
```

### Install tmux plugins

Press:

```
Ctrl + b, then Shift + i
```

### Start logging

```
Ctrl + b, then Shift + p
```

### Stop logging

```
Ctrl + b, then Shift + p
```

---

## Tmux Logging Shortcuts

| Action | Keybinding |
|------|--------|
| Start/Stop logging | Ctrl + b → Shift + p |
| Save entire pane | Ctrl + b → Alt + Shift + p |
| Capture pane | Ctrl + b → Alt + p |
| Reload config | Ctrl + b → r |

---

## VMware Shared Folder

By default, the script expects:

```
/mnt/hgfs/<SHARE_NAME>
```

You can modify this in the script:

```
SHARE_NAME="Shared"
```

If no shared folder is detected, it falls back to:

```
~/pentest-data
```

---

## Recommended Workflow

1. Deploy Kali VMware image
2. Update the system
3. Run this script and accept or change the prompted defaults
4. Optionally run PimpMyKali
5. Start assessments:

```
assess <client>
```

---

## Design Goals

- Keep Kali default environment intact
- Add structure without breaking workflows
- Ensure full logging and traceability
- Store all data in a backup-friendly location
- Reduce setup time per engagement

---

## Disclaimer

This script is intended for authorized security testing only. Use it only on systems you have permission to test.
