---
name: termux-environment
description: Verified facts about the Termux runtime on Android - $PREFIX and $HOME layout, absent FHS paths, shebangs and termux-exec, dash as sh, packages and architectures, shared-storage limits, Termux:API, Boot, services, process killing, detection, device facts. Use when code or config depends on paths, permissions, packages, storage, exec, or background processes that differ from desktop Linux. Facts only - to write code use termux-scripting.
---

# Termux environment

Facts were verified against official Termux sources (list: `references/runtime-facts.md`). For anything not listed here, search the web (Termux wiki, termux-packages, termux-app) before relying on it. Device-only behavior cannot be proven from a host.

Research authority: search the web yourself when docs or dependency facts are missing or stale (primary sources first: Termux wiki, termux-packages, termux-app, Android and shell manuals); cite URLs; never guess.

## Core facts
- `$PREFIX` = `/data/data/com.termux/files/usr`; `$HOME` = `/data/data/com.termux/files/home` (outside the prefix). `$PREFIX/bin` combines `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`; `$PREFIX/tmp` combines `/tmp` and `/var/tmp` (erased on each app restart); `$PREFIX/var/run` replaces `/run`; `$PREFIX/etc`, `$PREFIX/var`, `$PREFIX/lib`, `$PREFIX/share` hold the Termux equivalents (Android's `/etc` is a symlink to `/system/etc`, not Termux configuration). The Termux app exports `HOME`, `PREFIX`, `TMPDIR`, and `TERMUX_VERSION`.
- FHS paths are absent or restricted: do not hard-code `/tmp`, `/usr`, `/etc`, `/bin`, `/home`; use `$TMPDIR`, `$PREFIX`, `$HOME`.
- Exec: `termux-exec` is loaded through `LD_PRELOAD` and overrides the `exec()` family (not direct `execve` syscalls), so `#!/bin/sh` and `#!/usr/bin/env x` resolve to `$PREFIX/bin`. Without it, `/bin/*` and `/usr/bin/*` shebangs fail with `No such file or directory` or run Android's `/system/bin/*` binary of the same name. A `$PREFIX` shebang needs no help. Do not depend on Android's `/system/bin/sh`.
- `sh` in `$PREFIX/bin` is dash (package `dash`, `TERMUX_PKG_ESSENTIAL=true`; version 0.5.13.5 in termux-packages master, so `set -o pipefail` exists there; the device may differ). Verify on device: `readlink "$PREFIX/bin/sh"`, `dpkg -s dash`.
- Architectures: aarch64 (default), arm, i686, x86_64. libc is bionic, not glibc.
- Packages: `pkg install|update|upgrade|search|show`; `termux-change-repo` switches mirrors. Packages are built for the `com.termux` prefix.
- Installation sources: F-Droid or GitHub releases. The Google Play build is a separate experimental build; do not mix sources (signing and `sharedUserId` differ).
- Storage: `termux-setup-storage` creates `~/storage/*` symlinks into shared storage (`/storage/emulated/0`). Shared storage is mounted noexec, cannot hold symlinks, has case-insensitive names, and `chmod` fails there ("Operation not permitted"). Keep scripts, state, and symlink targets in `$HOME` or `$PREFIX`; a symlink in `$HOME` may point into shared storage. Pass a file in shared storage to an interpreter (`sh file`) instead of executing it.
- Termux:API: `termux-*` API commands need the Termux:API Android app, the `termux-api` package, and Android permissions. Guard each use with `command -v` and provide a fallback. Other `termux-*` commands (`termux-open`, `termux-wake-lock`, `termux-reload-settings`, `termux-setup-storage`, `termux-fix-shebang`) come from `termux-tools`.
- Settings: `~/.termux/termux.properties`, `colors.properties`, `font.ttf`; apply with `termux-reload-settings` (some need an app restart).
- Boot and services: Termux:Boot runs scripts in `~/.termux/boot/` at device boot (start the app once from its launcher icon; call `termux-wake-lock` first in a script that must keep the device awake); `termux-services` (depends on `runit`) provides service management.
- Android 12+ kills phantom processes above a combined limit of 32 across apps, and processes with excessive CPU use; symptom `[Process completed (signal 9) - press Enter]`.
- Detect Termux: `[ -n "${TERMUX_VERSION:-}" ]` and `$PREFIX`; `termux-info` prints versions and architecture.
- Host testing: stub `termux-*` (see `termux-scripting` `sandbox-run`); the Termux container has no Android runtime.
- Device facts: have the user run `sh scripts/device-facts.sh` in Termux (copy the file or paste its content) and paste the output. It is read-only, makes no Termux:API call, and settles device-only questions: dash version (`pipefail`), `LINENO`, architecture, Android SDK, termux-exec, Termux:API presence, storage setup.

## Decision table
| Situation | Do |
|---|---|
| Temp file | `mktemp` under `$TMPDIR`; trap cleanup |
| Script or executable file | keep it in `$HOME`; `chmod +x` there |
| Command that may be missing | `command -v x >/dev/null 2>&1 \|\| { echo "x missing: pkg install <pkg>" >&2; exit 1; }` |
| Android feature (toast, notification, clipboard, battery) | Termux:API behind a guard, with a fallback |
| Long-running background task | document wake-lock and the killer; do not promise reliability |
| Unsure about a fact | search official sources; cite the URL in notes |

## Gotchas
- A literal `/bin/sh` is Android's shell unless termux-exec intercepts it; scripts must not rely on either.
- `/sdcard` and `~/storage/*` paths in `chmod`, `ln -s`, `git clone`, or exec fail with "Operation not permitted" or are refused.
- CRLF in a shebang yields `bad interpreter`.
- `pkg` wraps `apt`: it selects a mirror and refreshes stale package lists before `install` and `search`, and `pkg upgrade` runs `apt update` then `apt full-upgrade`. Prefer it over bare `apt`.
- A feature needing root is out of scope unless the user states the device is rooted.
