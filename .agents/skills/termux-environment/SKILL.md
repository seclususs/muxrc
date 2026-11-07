---
name: termux-environment
description: Verified Termux and Android runtime facts, rooted or not: paths, exec limits, dash as sh, packages, storage, su, Termux:API, process kills, SSH device checks. Use when code depends on device behavior.
---

# Termux environment

Facts were verified against official Termux, Android, and root-tool sources (list: `references/runtime-facts.md`). For anything not listed here, search the web before relying on it. Device-only behavior cannot be proven from a host (see Device checks over SSH).

## Core facts
- `$PREFIX` = `/data/data/com.termux/files/usr`; `$HOME` = `/data/data/com.termux/files/home` (outside the prefix). `$PREFIX/bin` combines `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`; `$PREFIX/tmp` combines `/tmp` and `/var/tmp` (erased on each app restart); `$PREFIX/var/run` replaces `/run`; `$PREFIX/etc`, `$PREFIX/var`, `$PREFIX/lib`, `$PREFIX/share` hold the Termux equivalents (Android's `/etc` is a symlink to `/system/etc`, not Termux configuration).
- The app exports `HOME`, `PREFIX`, `TMPDIR`, `TERMUX_VERSION`. The wiki adds `TERMUX__PREFIX`, `TERMUX__HOME`, `TERMUX__ROOTFS` and deprecates `PREFIX` from app v0.119.0, which exists only as beta (latest stable: v0.118.3), so `$PREFIX` stays the portable choice.
- `PATH` holds only `$PREFIX/bin` on Android 7 and later; `/system/bin` is not in it. Android binaries need the absolute path, and `LD_LIBRARY_PATH` and `LD_PRELOAD` unset when run from Termux.
- FHS paths are absent or restricted: do not hard-code `/tmp`, `/usr`, `/etc`, `/bin`, `/home`; use `$TMPDIR`, `$PREFIX`, `$HOME`.
- Exec: `termux-exec` is loaded through `LD_PRELOAD` and overrides the `exec()` family (not direct `execve` syscalls), so `#!/bin/sh` and `#!/usr/bin/env x` resolve to `$PREFIX/bin`. Without it, `/bin/*` and `/usr/bin/*` shebangs fail with `No such file or directory` or run Android's `/system/bin/*` binary of the same name. A `$PREFIX` shebang needs no help. Do not depend on Android's `/system/bin/sh`.
- Android 10+ forbids executing app data files for apps with `targetSdkVersion` 29 or higher. The termux-app source sets `targetSdkVersion` 28, so `$PREFIX` binaries run directly; a build with a higher target needs the `termux-exec` linker workaround.
- `sh` in `$PREFIX/bin` is dash (package `dash`, essential; 0.5.13.5 in termux-packages master, so `set -o pipefail` exists there; the device may differ). Verify on device: `readlink "$PREFIX/bin/sh"`, `dpkg -s dash`.
- `bash` (package `bash`, essential) is 5.3.20 and `zsh` (optional, `pkg install zsh`) is 5.9.2 in termux-packages master; the device may differ (`bash --version`, `zsh --version`).
- Architectures: aarch64 (default), arm, i686, x86_64. libc is bionic, not glibc.
- Packages: `pkg` wraps `apt` (both exist; Termux also has a pacman-based variant, see `TERMUX_APP_PACKAGE_MANAGER`). `pkg install|update|upgrade|search|show`; `termux-change-repo` switches mirrors. Packages are built for the `com.termux` prefix.
- Default install: `termux-tools` depends on coreutils, findutils, grep, sed, gawk, diffutils, tar, gzip, bzip2, xz-utils, less, procps, psmisc, util-linux, curl, dialog, dash, termux-core, termux-exec, termux-am. Not on that list (install with `pkg`): git, python, jq, zsh, termux-api, sudo.
- Installation sources: F-Droid or GitHub releases. The Google Play build is separate; do not mix sources (signing differs).
- Storage: `termux-setup-storage` creates `~/storage/*` symlinks (`shared`, `documents`, `downloads`, `dcim`, `pictures`, `music`, `movies`, `podcasts`, `external-N`) into shared storage. Shared storage is mounted noexec, cannot hold symlinks, has case-insensitive names, and `chmod` fails there ("Operation not permitted"). Keep scripts, state, and symlink targets in `$HOME` or `$PREFIX`; a symlink in `$HOME` may point into shared storage. Pass a file in shared storage to an interpreter (`sh file`) instead of executing it.
- Termux:API: `termux-*` API commands need the Termux:API Android app, the `termux-api` package, and Android permissions. Guard each use with `command -v` and provide a fallback. Other `termux-*` commands (`termux-open`, `termux-wake-lock`, `termux-reload-settings`, `termux-setup-storage`, `termux-fix-shebang`) come from `termux-tools`.
- Settings: `~/.termux/termux.properties`, `colors.properties`, `font.ttf`; apply with `termux-reload-settings` (some need an app restart).
- Boot and services: Termux:Boot runs scripts in `~/.termux/boot/` at device boot (start the app once from its launcher icon; call `termux-wake-lock` first in a script that must keep the device awake); `termux-services` (depends on `runit`) provides service management.
- Android 12+ kills phantom processes above a combined limit of 32 across apps, and processes with excessive CPU use; symptom `[Process completed (signal 9) - press Enter]`.
- Detect Termux: `[ -n "${TERMUX_VERSION:-}" ]` and `$PREFIX`; `termux-info` prints versions and architecture.
- Terminal width: the default font is 12dp and a glyph is about 0.6 of the font size wide, so a 360dp phone shows about 50 columns, a 411dp phone about 57, and a 360dp phone zoomed to 16dp about 37. The log limit in the core policy rests on this estimate; measure the real width with `tput cols` in the app.

## Root and non-root
- Termux itself does not need root. The app runs under its own Android user id (`u0_aNNN`); it can access only files with the same owner and a compatible SELinux context. Root bypasses that sandbox.
- `$PREFIX/bin/su` exists on every install (package `termux-tools`). It looks for a su binary in `/debug_ramdisk/su`, `/sbin/su`, `/system/sbin/su`, `/system/bin/su`, `/system/xbin/su`, `/su/bin/su`, `/magisk/.core/bin/su`, unsets `LD_LIBRARY_PATH` and `LD_PRELOAD`, sets `PATH` to Android directories, and runs the binary. With none found it prints "No su program found on this device" and exits 1. Consequence: `command -v su` succeeds without root; test the result of `su -c true` (with a timeout, since a root manager may ask for approval).
- Inside `su`, `PATH` has no `$PREFIX/bin` and `LD_PRELOAD` is unset, so Termux commands need an explicit `PATH` (and `LD_PRELOAD` for shebang resolution). A generic su client such as Magisk's inherits the caller's environment and sets `HOME`, `USER`, `LOGNAME`, `SHELL` for the target user unless `-p`/`-m`/`--preserve-environment` is given; other su implementations differ, so check on the device.
- Files that a root process creates in `$HOME` or `$PREFIX` keep root ownership; non-root app processes may then fail to read or modify them, which can break the Termux environment (the Termux wiki advises against root unless needed). Check with `ls -ln`. `pkg`, `apt`, and `pacman` are patched to refuse to run as root: run package commands without `su`.
- `pkg install root-repo` adds the repository of packages meant for rooted devices.
- `sudo` (agnostic-apollo/sudo, package `sudo`) is an optional wrapper around `su` for rooted devices. It needs a `su` binary that supports `-c`, `--shell`, `--preserve-environment`, and `--mount-master` (Magisk and SuperSU do), ideally with root permission granted to Termux. A su wrapper may set `HOME` to `~/.suroot` to keep root-owned files apart. Code calls plain `su -c` and handles failure; it does not require the wrapper.
- Default: write code that works without root, detect root explicitly, and degrade when it is missing. A feature that needs root states so.

## Device checks over SSH
A host run shows syntax and logic, not Termux. When a check needs the device (termux-exec, storage, root, Termux:API, the device's dash), ask once per conversation, in the user's language: "Can I reach your Termux device over SSH?" If the user answers with a command, for example `ssh termux` (an alias from the user's own SSH config), call it `$DEV` and use it exactly as given. Never edit SSH config or keys and never guess a host. If the answer is no, list the check with its exact command for the user to run.
- Probe first, read-only: `$DEV 'uname -o; echo "$PREFIX"; echo "$TMPDIR"'` must print `Android` and two paths; otherwise stop and report. When `$DEV` starts with `ssh`, add `-o BatchMode=yes -o ConnectTimeout=10` right after `ssh`, so a missing key fails instead of waiting for a password.
- Run code only inside a temporary directory that the same command removes, with `HOME` redirected into it. Send the files as a tar stream so nothing else is written:
  `tar -c -C DIR FILE... | $DEV 'd=$(mktemp -d "${TMPDIR:?}/agent.XXXXXX") || exit 1; trap "rm -rf \"$d\"" EXIT HUP INT TERM; tar -x -C "$d" && cd "$d" && mkdir home && HOME="$d/home" timeout 60 sh ./SCRIPT ARGS'`
  The command's exit status is the script's. The trap removes the directory after success, failure, timeout, or a dropped connection (tested against OpenSSH with bash, dash, and zsh as login shell; not on a device).
- Afterwards `$DEV 'ls -d "${TMPDIR:?}"/agent.* 2>/dev/null'` must print nothing; report that.
- Without the user's approval, run nothing that changes the device outside that directory: `pkg` or `apt` installs, writes under `$PREFIX`, `~/.termux`, or storage, services, `su`, kill, reboot. Read each script before sending it; one that does any of those runs only in `sandbox-run`.
- Run the pipe from a POSIX shell (Git Bash or WSL on Windows): PowerShell 5.1 corrupts binary pipelines. Termux's sshd listens on port 8022 and keeps `PATH`, `PREFIX`, `TMPDIR`, `LANG`, and `TERMUX_*` in the session.

## Decision table
| Situation | Do |
|---|---|
| Temp file | `mktemp` under `$TMPDIR`; trap cleanup |
| Script or executable file | keep it in `$HOME`; `chmod +x` there |
| Command that may be missing | `command -v x >/dev/null 2>&1 \|\| { echo "x missing: pkg install <pkg>" >&2; exit 1; }` |
| Android feature (toast, notification, clipboard, battery) | Termux:API behind a guard, with a fallback |
| Root needed | `su -c` behind a status check, with a non-root path |
| Long-running background task | document wake-lock and the killer; do not promise reliability |
| Behavior only the device shows | ask for SSH access (Device checks over SSH) |
| Unsure about a fact | search official sources; cite the URL in notes |

## Gotchas
- A literal `/bin/sh` is Android's shell unless termux-exec intercepts it; scripts must not rely on either.
- `/sdcard` and `~/storage/*` paths in `chmod`, `ln -s`, `git clone`, or exec fail with "Operation not permitted" or are refused.
- CRLF in a shebang yields `bad interpreter`.
- `pkg` selects a mirror and refreshes stale package lists before `install` and `search`, and `pkg upgrade` runs `apt update` then `apt full-upgrade`. Prefer it over bare `apt`.
