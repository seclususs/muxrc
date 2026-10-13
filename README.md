# muxrc

My personal Termux environment configuration. Built for quick setup and automated installation.

## Installation

1. Clone the repository:

```bash
git clone https://github.com/seclususs/muxrc.git
```

2. Run the installation script:

```bash
cd muxrc
bash install.sh
```

## Usage

Restart Termux after installation to apply changes.

### Daily Workflow & System

- `su` and `sudo <command>` — Run commands or open an interactive root shell.
- `trash <file>` and `untrash` — Delete files safely and restore them anytime.
- `notify-task <command>` — Run a task in the background and get notified when it finishes.
- `net-info` — Show your local IP and ready-to-use SSH connection command.
- `clip-pick` — Search and paste from your clipboard history (requires `clip-watch`).
- `ex <file>` — Extract any archive format (.zip, .tar, .7z, etc.) with a single command.
- `cmd-do <intent>` — Convert natural language intent into shell commands.
- `cmd-fix` (or `??`) — Diagnose previous runtime error (or piped error log) and suggest the fix.
- `cmd-ask [question]` — Ask technical questions with auto file inspection, piped STDIN, and Google search.
- `ai-toggle` — Turn Gemini AI assistant and auto-correction on or off.
- `ai-model [name]` — View or switch the active Gemini AI model.
- `muxrc-sync` — Update dotfiles and plugins to the latest version.
- Keyboard macros — Swipe up on `ESC` to jump to `~/Workspace` and `END` to toggle wakelock.

### Privacy & Media Tools

- `media-crypt <file>` and `media-decrypt <file>` — Encrypt and decrypt private files.
- `video-compress <file>` — Compress video to HEVC with full metadata preservation.
- `clean-meta <dir>` — Remove camera and location metadata from photos.
- `spoof-meta <preset> <file>` — Replace photo metadata with dummy device info.
- `date-sync <target>` — Sync photo metadata dates with file timestamps.
- `rename-by-date <dir> <prefix>` — Organize photos by their capture date.
- `clean-dupes <dir>` — Find and clean up duplicate files.
- `shred-file <file>` — Permanently destroy sensitive files beyond recovery.
- `stego-vault` — Hide or extract secret text and files inside pictures.
- `net-sweep` — Discover devices connected to your local network.
- `tor-start` and `tor-stop` — Start or stop an anonymous Tor proxy session.
- `tor-run <command>` — Run any command anonymously through Tor via ProxyChains.
- `tor-check` — Verify Tor network connectivity and inspect active exit IP.

## Disclaimer

Tailored strictly for my personal workflow and device environment. Use at your own risk.
