# termux-sim: what it models

`scripts/termux-sim.sh` builds a temporary Termux-like tree, installs command stand-ins, and runs the target through `termux-scripting/scripts/sandbox-run.sh`. Use it when a check would otherwise need a device. It does not replace one.

## Run
```text
sh scripts/termux-sim.sh [options] -- SCRIPT [ARGS...]
sh scripts/termux-sim.sh [options] -c 'SHELL TEXT'
sh scripts/termux-sim.sh [options] --facts
```
Options: `--root`, `--profile FILE`, `--arch A`, `--sdk N`, `--android V`, plus the sandbox-run options `--stub`, `--stub-termux`, `--seed`, `--env`, `--timeout`, `--dialect`, `--twice`, `--keep` (kept sandboxes go to `.artifacts/sandbox/`). Exit status is the script's own. On Windows, `termux-sim.ps1` needs a POSIX shell (Git for Windows or WSL).

## Modeled
| Area | Behavior | Basis |
|---|---|---|
| Variables | `HOME`, `PREFIX`, `TMPDIR`, `TERMUX_VERSION`, `TERMUX__ROOTFS`, `TERMUX__PREFIX`, `TERMUX__HOME`, `TERMUX_APP_PACKAGE_MANAGER`, `ANDROID_ROOT`, `ANDROID_DATA`, `SHELL`; `TERMUX_SIM=1` marks the simulation | Termux wiki, termux-info |
| `uname` | `-o` Android, `-m` from the profile, `-s` Linux, `-n` localhost | profile |
| `getprop` | release, SDK, manufacturer, model, ABI lists | profile |
| `id`, `whoami` | app uid and name (`u0_aNNN`); uid 0 inside `su` | Android app sandbox |
| `su` | Termux wrapper text and exit 1 without root. With `--root`: the command runs with `PATH` and variables as a generic su client leaves them (see below) | termux-tools `su.in`, Magisk `su` |
| `pkg`, `apt`, `apt-get` | install and remove are recorded (`dpkg -s` reflects them); update and upgrade are no-ops; other subcommands exit 1 with a note | Termux wiki |
| `dpkg`, `dpkg-query` | architecture, installed versions from the profile (`-W -f`, `-s`, `-l`) | profile |
| `termux-info` | section layout of the official script | termux-tools `termux-info.in` |
| `termux-setup-storage` | creates `~/storage/*` links into a simulated shared storage | termux-app `TermuxInstaller` |
| Shared storage | `chmod` and `ln` refuse with "Operation not permitted" inside it | Termux wiki, termux-packages issue 4728 |
| `sudo`, `doas` | always stubbed with exit 127, so a script cannot run them on the host | safety |

Root model (`--root`): `su -c CMD` runs CMD with `TERMUX_SIM_SU=1`; `LD_LIBRARY_PATH` and `LD_PRELOAD` unset; `PATH` without the Termux `bin` directory (host directories stand in for `/system/bin`); `HOME`, `USER`, `LOGNAME`, `SHELL` set for root (a sim directory) unless `-p`, `-m`, or `--preserve-environment`; `PREFIX` and `TMPDIR` inherited. Only root is simulated as the target user.

## Not modeled
Android kernel and SELinux; bionic libc; `termux-exec` and shebang rewriting; the W^X exec restriction; file ownership and permissions of a real app uid; Termux:API; literal `/data/data/com.termux` paths (not remapped); the real `$PREFIX/bin` command set. Host commands stay on `PATH`, so `command -v` may find a tool that a fresh Termux lacks; `lint-shell` rule T003 covers the common names statically. Shell behavior comes from the host shell: when the profile's dash is newer than the host's (for example `pipefail`), the tool prints a note.

## Profile
Default: `assets/sim/profile.env` (key=value, same keys as `device-facts.sh`). Order of precedence: defaults, `--root`, `--profile FILE`, `--arch`/`--sdk`/`--android`. Values in the defaults are placeholders, except `termux.version` and `pkg.*`, which follow the latest app release and termux-packages master on the day the file was written. For a specific device, run `device-facts.sh` there and pass its output with `--profile`.

## Reading results
Report simulation results as "simulated, profile X", never as device results. A script that passes here still needs the device checks that `sandbox-run` lists. A script that fails here with a Termux-specific message (for example the `su` text, a refused `chmod` in storage) points to a real portability issue; confirm on a device when the cost of being wrong is high.
