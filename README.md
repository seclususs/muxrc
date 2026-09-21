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

- Enter fake shell root mode: `su`
- Run single root command: `sudo <command>`
- Safe file deletion: `trash <file>` and `untrash`
- Long-running task wrapper: `notify-task <command>`
- SSH network connection helper: `net-info`
- Clipboard history picker: `clip-pick` (requires running `clip-watch`)
- Toggle Gemini auto-correct hook: `ai-toggle`
- Storage shortcuts: `~/Workspace`
- Extra-keys macros: Swipe up on `ESC` (cd Workspace) and `END` (wakelock)

## Disclaimer

Tailored strictly for my personal workflow and device environment. Use at your own risk.
