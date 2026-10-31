# Fallback matrix

Resolve each need from the `cap.*` keys of the detection output. "Partial" means state reduced coverage in the report.

| Need | Providers, in order | When none is available | Coverage |
|---|---|---|---|
| Lint sh/bash | ShellCheck | built-in heuristics (`lint-shell` falls back automatically) | partial: no data-flow checks |
| Format sh/bash | `format-shell` (shfmt with project `.editorconfig`, no style flags) | manual check against `.editorconfig` | unverified formatting |
| Format zsh | `shfmt -d FILE.zsh` (no flags; diff only, never write) | match existing style by hand | advisory |
| Syntax, POSIX sh | `dash -n` (parse errors only), `busybox sh -n`, `sh -n` (may be bash: weak) | heuristic B-rules; ShellCheck `-s sh` reports bashisms | partial: `-n` passes `[[ ]]`, `${v//a/b}`, `source`, `$'..'`, `&>` |
| Syntax, bash | `bash -n` | ShellCheck | partial |
| Syntax, zsh | `zsh -n` | heuristic Z-rules | partial. Windows: WSL, or MSYS2 `pacman -S zsh` |
| Complete diff | `git` through `diff-collect` | `diff -u` (POSIX) or `Compare-Object` (PowerShell) on two copies | partial: no statistics check |
| Search | `rg`, `grep`, PowerShell `Select-String` | | |
| JSON | `jq`, `python3`, `node`, PowerShell `ConvertFrom-Json` | | |
| Archive | `zip`, `tar`, PowerShell `Compress-Archive` | | keep the directory structure |
| Termux-like run | `cap.sandbox` (sandbox-run stubs), `termux-sim` (documented Termux and root behavior), `cap.termux_container` (docker) | give the user device commands | stub-based or simulated only |
| Behavior snapshot | `behavior-snapshot` (POSIX shell plus the shell under test) | run the cases by hand in `sandbox-run` or on a device and compare | partial |
| Real device check | `adb push` to shared storage, then copy into Termux `$HOME` | user runs the commands | |
| POSIX shell on Windows | Git Bash, WSL, MSYS2 | skip sandbox-run, termux-sim, trace-run, behavior-snapshot; use a container or device | partial |
| LF endings | `.gitattributes` plus editor setting; verify with lint `E001` | | |
| Tool self-check | `selftest.sh` or `selftest.ps1` | run each tool with `--help` and one fixture by hand | partial |

## Notes
- Termux container: the official `termux/termux-docker` project (https://github.com/termux/termux-docker); verify image name and tags in its README. It has no Android runtime, so `termux-*` API commands are absent; `aarch64` or `arm` images on x86 hosts need QEMU and may need privileged mode.
- Device transfer example: `adb push file /sdcard/Download/`, then in Termux (after `termux-setup-storage`) `cp ~/storage/downloads/file ~/`.
- Install policy: do not install host packages without asking; prefer a fallback first.
