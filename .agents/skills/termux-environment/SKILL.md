---
name: termux-environment
description: Verified facts about the Termux runtime on Android, rooted and non-rooted - $PREFIX and $HOME layout, absent FHS paths, shebangs and termux-exec, dash as sh, packages and architectures, shared-storage limits, su behavior and root caveats, Termux:API, Boot, process killing - plus termux-sim, an offline simulation of that environment on the host (uname, getprop, id, su, pkg, storage) for scripts and checks that would otherwise need a physical device. Use when code, config, or a question depends on paths, permissions, packages, storage, exec, root, or background processes that differ from desktop Linux. To write code use termux-scripting.
---

# Termux environment

Facts were verified against official Termux, Android, and root-tool sources (list: `references/runtime-facts.md`). For anything not listed here, search the web before relying on it. Device-only behavior cannot be proven from a host.

## Core facts
- `$PREFIX` = `/data/data/com.termux/files/usr`; `$HOME` = `/data/data/com.termux/files/home` (outside the prefix). `$PREFIX/bin` combines `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`; `$PREFIX/tmp` combines `/tmp` and `/var/tmp` (erased on each app restart); `$PREFIX/var/run` replaces `/run`; `$PREFIX/etc`, `$PREFIX/var`, `$PREFIX/lib`, `$PREFIX/share` hold the Termux equivalents (Android's `/etc` is a symlink to `/system/etc`, not Termux configuration).
- The app exports `HOME`, `PREFIX`, `TMPDIR`, `TERMUX_VERSION`. From app v0.119.0 the documented names are `TERMUX__PREFIX`, `TERMUX__HOME`, `TERMUX__ROOTFS`, and `PREFIX` is marked deprecated; the latest release is v0.118.3, so `$PREFIX` stays the portable choice.
- `PATH` holds only `$PREFIX/bin` on Android 7 and later; `/system/bin` is not in it. Android binaries need the absolute path, and `LD_LIBRARY_PATH` and `LD_PRELOAD` unset when run from Termux.
- FHS paths are absent or restricted: do not hard-code `/tmp`, `/usr`, `/etc`, `/bin`, `/home`; use `$TMPDIR`, `$PREFIX`, `$HOME`.
- Exec: `termux-exec` is loaded through `LD_PRELOAD` and overrides the `exec()` family (not direct `execve` syscalls), so `#!/bin/sh` and `#!/usr/bin/env x` resolve to `$PREFIX/bin`. Without it, `/bin/*` and `/usr/bin/*` shebangs fail with `No such file or directory` or run Android's `/system/bin/*` binary of the same name. A `$PREFIX` shebang needs no help. Do not depend on Android's `/system/bin/sh`.
- Android 10+ forbids executing app data files for apps with `targetSdkVersion` 29 or higher. The termux-app source sets `targetSdkVersion` 28, so `$PREFIX` binaries run directly; a build with a higher target needs the `termux-exec` linker workaround.
- `sh` in `$PREFIX/bin` is dash (package `dash`, essential; 0.5.13.5 in termux-packages master, so `set -o pipefail` exists there; the device may differ). Verify on device: `readlink "$PREFIX/bin/sh"`, `dpkg -s dash`.
- Architectures: aarch64 (default), arm, i686, x86_64. libc is bionic, not glibc.
- Packages: `pkg` wraps `apt` (both exist; Termux also has a pacman-based variant, see `TERMUX_APP_PACKAGE_MANAGER`). `pkg install|update|upgrade|search|show`; `termux-change-repo` switches mirrors. Packages are built for the `com.termux` prefix.
- Default install: `termux-tools` depends on coreutils, findutils, grep, sed, gawk, diffutils, tar, gzip, bzip2, xz-utils, less, procps, psmisc, util-linux, curl, dialog, dash. Not on that list (install with `pkg`): git, python, jq, zsh, termux-api, sudo.
- Installation sources: F-Droid or GitHub releases. The Google Play build is separate; do not mix sources (signing differs).
- Storage: `termux-setup-storage` creates `~/storage/*` symlinks (`shared`, `documents`, `downloads`, `dcim`, `pictures`, `music`, `movies`, `podcasts`, `external-N`) into shared storage. Shared storage is mounted noexec, cannot hold symlinks, has case-insensitive names, and `chmod` fails there ("Operation not permitted"). Keep scripts, state, and symlink targets in `$HOME` or `$PREFIX`; a symlink in `$HOME` may point into shared storage. Pass a file in shared storage to an interpreter (`sh file`) instead of executing it.
- Termux:API: `termux-*` API commands need the Termux:API Android app, the `termux-api` package, and Android permissions. Guard each use with `command -v` and provide a fallback. Other `termux-*` commands (`termux-open`, `termux-wake-lock`, `termux-reload-settings`, `termux-setup-storage`, `termux-fix-shebang`) come from `termux-tools`.
- Settings: `~/.termux/termux.properties`, `colors.properties`, `font.ttf`; apply with `termux-reload-settings` (some need an app restart).
- Boot and services: Termux:Boot runs scripts in `~/.termux/boot/` at device boot (start the app once from its launcher icon; call `termux-wake-lock` first in a script that must keep the device awake); `termux-services` (depends on `runit`) provides service management.
- Android 12+ kills phantom processes above a combined limit of 32 across apps, and processes with excessive CPU use; symptom `[Process completed (signal 9) - press Enter]`.
- Detect Termux: `[ -n "${TERMUX_VERSION:-}" ]` and `$PREFIX`; `termux-info` prints versions and architecture.

## Root and non-root
- Termux itself does not need root. The app runs under its own Android user id (`u0_aNNN`); it can access only files with the same owner and a compatible SELinux context. Root bypasses that sandbox.
- `$PREFIX/bin/su` exists on every install (package `termux-tools`). It looks for a su binary in `/debug_ramdisk/su`, `/sbin/su`, `/system/sbin/su`, `/system/bin/su`, `/system/xbin/su`, `/su/bin/su`, `/magisk/.core/bin/su`, unsets `LD_LIBRARY_PATH` and `LD_PRELOAD`, sets `PATH` to Android directories, and runs the binary. With none found it prints "No su program found on this device" and exits 1. Consequence: `command -v su` succeeds without root; test the result of `su -c true` (with a timeout, since a root manager may ask for approval).
- Inside `su`, `PATH` has no `$PREFIX/bin` and `LD_PRELOAD` is unset, so Termux commands need an explicit `PATH` (and `LD_PRELOAD` for shebang resolution). A generic su client such as Magisk's inherits the caller's environment and sets `HOME`, `USER`, `LOGNAME`, `SHELL` for the target user unless `-p`/`-m`/`--preserve-environment` is given; other su implementations differ, so check on the device.
- Files that a root process creates in `$HOME` or `$PREFIX` keep root ownership; non-root app processes may then fail to read or modify them, which can break the Termux environment (the Termux wiki advises against root unless needed). Check with `ls -ln`. `pkg`, `apt`, and `pacman` are patched to refuse to run as root: run package commands without `su`.
- `pkg install root-repo` adds the repository of packages meant for rooted devices.
- `sudo` (agnostic-apollo/sudo, package `sudo`) is an optional wrapper around `su` for rooted devices. It needs a `su` binary that supports `-c`, `--shell`, `--preserve-environment`, and `--mount-master` (Magisk and SuperSU do), ideally with root permission granted to Termux. A su wrapper may set `HOME` to `~/.suroot` to keep root-owned files apart. Code calls plain `su -c` and handles failure; it does not require the wrapper.
- Default: write code that works without root, detect root explicitly, and degrade when it is missing. A feature that needs root states so.

## Simulate on the host
No device at hand: `sh scripts/termux-sim.sh` (or `.ps1`) runs a script, a snippet, or the fact collector in a simulated Termux. Details and limits: `references/simulation.md`.
- Script: `sh scripts/termux-sim.sh [--root] -- path/to/script.sh args`
- Snippet: `sh scripts/termux-sim.sh [--root] -c 'uname -o; su -c id'`
- Facts: `sh scripts/termux-sim.sh [--root] --facts` (output carries `sim=yes`)
- Match a real device: pass the output of `device-facts.sh` as `--profile FILE`.
It reproduces documented behavior (paths, variables, `uname -o`, `getprop`, `id`, `su`, `pkg`, `dpkg`, `termux-info`, storage refusals). It does not reproduce the Android kernel, SELinux, bionic, termux-exec, or Termux:API; anything that depends on those is listed as "needs device".

## Device facts
Have the user run `sh scripts/device-facts.sh` in Termux (copy the file or paste its content) and paste the output. It is read-only, makes no Termux:API call, and settles device-only questions: dash version (`pipefail`), `LINENO`, architecture, Android SDK, termux-exec, Termux:API presence, storage setup.

## Decision table
| Situation | Do |
|---|---|
| Temp file | `mktemp` under `$TMPDIR`; trap cleanup |
| Script or executable file | keep it in `$HOME`; `chmod +x` there |
| Command that may be missing | `command -v x >/dev/null 2>&1 \|\| { echo "x missing: pkg install <pkg>" >&2; exit 1; }` |
| Android feature (toast, notification, clipboard, battery) | Termux:API behind a guard, with a fallback |
| Root needed | `su -c` behind a status check, with a non-root path |
| Long-running background task | document wake-lock and the killer; do not promise reliability |
| Unsure about a fact | search official sources; cite the URL in notes |

## Gotchas
- A literal `/bin/sh` is Android's shell unless termux-exec intercepts it; scripts must not rely on either.
- `/sdcard` and `~/storage/*` paths in `chmod`, `ln -s`, `git clone`, or exec fail with "Operation not permitted" or are refused.
- CRLF in a shebang yields `bad interpreter`.
- `pkg` selects a mirror and refreshes stale package lists before `install` and `search`, and `pkg upgrade` runs `apt update` then `apt full-upgrade`. Prefer it over bare `apt`.
