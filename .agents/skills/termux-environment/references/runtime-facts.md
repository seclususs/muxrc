# Runtime facts and sources

Load when a Termux claim must be justified or extended. Verified on 2026-11-04 against termux-packages b1bc9d9, termux-app 8629e63 (latest stable tag v0.118.3), and termux-tools 9b53fb1. Re-verify with a web search if a fact may have changed.

| Fact | Source |
|---|---|
| `$PREFIX`, `$HOME`, merged bin/tmp/etc/var/lib directories, bionic | https://github.com/termux/termux-packages/wiki/Termux-file-system-layout |
| termux-exec through `LD_PRELOAD`, `/bin` and `/usr/bin` shebang behavior, app data exec restrictions, external storage limits (noexec, no symlinks, case-insensitive) | https://github.com/termux/termux-packages/wiki/Termux-execution-environment , https://github.com/termux/termux-exec |
| Hard-coded FHS paths must be patched or avoided | https://github.com/termux/termux-packages/wiki/Common-porting-problems |
| `sh` is dash, `TERMUX_PKG_ESSENTIAL=true`, version | https://github.com/termux/termux-packages/blob/master/packages/dash/build.sh |
| `bash` essential and its version; `zsh` version | https://github.com/termux/termux-packages/blob/master/packages/bash/build.sh , https://github.com/termux/termux-packages/blob/master/packages/zsh/build.sh |
| `pipefail` in POSIX.1-2024, and the probe pattern | https://github.com/koalaman/shellcheck/wiki/SC3040 |
| dash 0.5.13.5 accepts `pipefail` and sets `$LINENO`; 0.5.12 does neither (tested by building the upstream tarball) | http://archive.ubuntu.com/ubuntu/pool/main/d/dash/ (`dash_0.5.13.5.orig.tar.gz`) |
| Architectures aarch64 (default), arm, i686, x86_64 | https://github.com/termux/termux-packages/wiki/Building-packages |
| `pkg`, mirrors, `termux-change-repo` | https://github.com/termux/termux-packages/wiki/Package-Management , https://github.com/termux/termux-packages/wiki/Mirrors |
| `HOME`, `PREFIX`, `TMPDIR`, `TERMUX_VERSION` exported by the app | https://github.com/termux/termux-app (`TermuxShellEnvironment.java`, `TermuxAppShellEnvironment.java` under `termux-shared`) |
| Installation sources, phantom process killer, signal 9 on Android 12+ | https://github.com/termux/termux-app (README) |
| `chmod` fails on shared storage (the wiki list of unsupported features contains a typo: one bullet reads "do support") | https://github.com/termux/termux-packages/issues/4728 |
| `termux.properties` keys and `termux-reload-settings`, other `termux-*` tools | https://github.com/termux/termux-tools |
| Termux:API commands | https://github.com/termux/termux-api-package |
| Boot scripts in `~/.termux/boot/` | https://github.com/termux/termux-boot |
| Services | https://github.com/termux/termux-services |
| Termux container, no Android runtime | https://github.com/termux/termux-docker |
| `termux-info` output and the `TERMUX_APP_PACKAGE_MANAGER` variable (apt or pacman) | https://github.com/termux/termux-tools (`scripts/termux-info.in`) |
| `$PREFIX/bin/su` wrapper: search paths, unset `LD_*`, Android `PATH`, "No su program found" | https://github.com/termux/termux-tools (`scripts/su.in`) |
| Generic su client: options, environment inheritance, `HOME`/`USER`/`LOGNAME`/`SHELL` unless `-p` | https://github.com/topjohnwu/Magisk (`docs/tools.md`, `native/src/core/su/su.cpp`) |
| Android app sandbox: unique uid per app, root bypasses it | https://source.android.com/docs/security/app-sandbox |
| Same-owner file access, `PATH` with only `$PREFIX/bin`, `LD_*` for Android binaries, `TERMUX__*` variables, `$PREFIX` deprecation from v0.119.0 | https://github.com/termux/termux-packages/wiki/Termux-execution-environment , https://github.com/termux/termux-packages/wiki/Termux-file-system-layout |
| `targetSdkVersion` 28 | https://github.com/termux/termux-app (`gradle.properties`) |
| `termux-tools` dependencies (default command providers), coreutils built without `pinky`, `df`, `users`, `who` | https://github.com/termux/termux-packages (`packages/termux-tools/build.sh`, `packages/coreutils/build.sh`) |
| `root-repo` package | https://github.com/termux/termux-packages (`packages/root-repo/build.sh`) |
| `sudo` package: rooted device, required `su` options, optional wrapper | https://github.com/agnostic-apollo/sudo (`site/pages/en/projects/docs/install/index.md`, `usage/index.md`), https://github.com/termux/termux-packages (`packages/sudo/build.sh`) |
| Su wrappers may set `HOME` to `~/.suroot`; `apt` and `pacman` refuse root; root-created files can break the environment | https://github.com/termux/termux-packages/wiki/Termux-file-system-layout |
| `~/storage/*` link names | https://github.com/termux/termux-app (`TermuxInstaller.java`) |
| Stable release v0.118.3; v0.119.0 only as beta tags | https://github.com/termux/termux-app/releases |
| Default font 12dp (`TermuxAppSharedPreferences.java`), columns = view width / glyph width of "X" (`TerminalView.java`, `TerminalRenderer.java`); the 0.6 glyph ratio is an estimate for monospace fonts | https://github.com/termux/termux-app (`termux-shared`, `terminal-view`) |
| sshd: port 8022, default `PATH` `$PREFIX/bin`, session keeps `PATH`, `PREFIX`, `TMPDIR`, `LANG`, `TERMUX_*`, `ANDROID_*` | https://github.com/termux/termux-packages (`packages/openssh/build.sh`, `sshd_config.patch`, `session.c.patch`) |

## Verification commands (on a device)
Run them through `$DEV` (SKILL.md, Device checks over SSH) or ask the user to run them:
`echo "$PREFIX $HOME $TMPDIR"` / `readlink "$PREFIX/bin/sh"` / `dpkg -s dash | grep Version` / `dash -c 'set -o pipefail && echo pipefail-ok; echo "LINENO=${LINENO-}"'` / `getprop ro.build.version.sdk` / `echo "$LD_PRELOAD"` (termux-exec) / `dpkg --print-architecture` / `command -v termux-toast` / `termux-info` / `id -u` / `su -c id` (rooted devices)
