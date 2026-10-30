# Runtime facts and sources

Load when a Termux claim must be justified or extended. Re-verify with a web search if a fact may have changed.

| Fact | Source |
|---|---|
| `$PREFIX`, `$HOME`, merged bin/tmp/etc/var/lib directories, bionic | https://github.com/termux/termux-packages/wiki/Termux-file-system-layout |
| termux-exec through `LD_PRELOAD`, `/bin` and `/usr/bin` shebang behavior, app data exec restrictions, external storage limits (noexec, no symlinks, case-insensitive) | https://github.com/termux/termux-packages/wiki/Termux-execution-environment , https://github.com/termux/termux-exec |
| Hard-coded FHS paths must be patched or avoided | https://github.com/termux/termux-packages/wiki/Common-porting-problems |
| `sh` is dash, `TERMUX_PKG_ESSENTIAL=true`, version | https://github.com/termux/termux-packages/blob/master/packages/dash/build.sh |
| `pipefail` in POSIX.1-2024 and dash 0.5.13 | https://github.com/koalaman/shellcheck/wiki/SC3040 |
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
| `~/storage/*` link names | https://github.com/termux/termux-app (`TermuxInstaller.java`) |

## Verification commands (on a device)
One shot: `sh scripts/device-facts.sh` (skill directory). Individually:
`echo "$PREFIX $HOME $TMPDIR"` / `readlink "$PREFIX/bin/sh"` / `dpkg -s dash | grep Version` / `dpkg --print-architecture` / `command -v termux-toast` / `termux-info` / `command -v getprop` / `id -u` / `su -c id` (rooted devices)
