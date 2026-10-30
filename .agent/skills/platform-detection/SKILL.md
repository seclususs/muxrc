---
name: platform-detection
description: Detects the development host (Linux, macOS, Windows, WSL, Git Bash, MSYS), its package manager, and available tools (ShellCheck, shfmt, dash, bash, zsh, git, PowerShell), and selects fallbacks for missing tools. Runs on initial turn, session start, or tool failure through using-termux-skills, and again when a host tool fails with "not found". Covers host tools only; a missing Termux command belongs to systematic-debugging or termux-environment.
---

# Platform detection

The host is where code is edited and checked; the target is Termux. Do not assume host OS, shell, or tools. Paths are relative to this skill directory.

## Steps
1. Pick the flavor:
   - POSIX shell present (`uname -s` works: Linux, macOS, WSL, Git Bash, MSYS, Cygwin): `sh scripts/detect-platform.sh --brief`
   - Windows PowerShell or cmd (`uname` not found): `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/detect-platform.ps1 --brief`; with PowerShell 7: `pwsh -NoProfile -File scripts/detect-platform.ps1 --brief`
   `--brief` replaces the per-tool lines with one `tool.missing` line; omit it to see every tool path.
2. Read the `key=value` output; reuse it across turns. The script is read-only and fast; run it on initial turn, session start, or when a tool fails unexpectedly.
3. For each step you need, read `cap.*` (best provider, or the fallback). Order and coverage effects: `references/fallback-matrix.md`.
4. Missing tool: use the fallback; do not stop. Report which checks ran with reduced coverage.
5. `hint.*` lines are suggestions. Offer them only if the user wants the tool; do not install system packages without approval; verify package ids with the package manager first.

## Verify the tools on this host
`sh scripts/selftest.sh` (and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/selftest.ps1`) builds a throwaway repository, runs each skill tool once, and prints PASS, FAIL, or SKIP per tool plus `SELFTEST pass=N fail=N skip=N`. Run it once on a new host, after installing or updating a tool, or when a script behaves unexpectedly. A SKIP names a missing prerequisite; a FAIL is a defect on this host: report it with the printed lines.

## Output keys
`host.os` linux|macos|windows|android; `host.env` native|wsl|git-bash|msys|cygwin|termux; `host.arch`; `host.pkgmgr`; `tool.NAME` path or `-` (`tool.missing` with `--brief`); `ver.shellcheck`, `ver.shfmt`; `cap.NAME` provider or `none`; `hint.NAME`; `run.scripts` sh|ps1. `--tools a,b` probes extra tools.

## Host command rules
- Every host script exists as `.sh` (needs a POSIX shell) and `.ps1` (Windows PowerShell 5.1+ or PowerShell 7+) with the same options, output, and exit codes. Exceptions: `device-facts.sh` runs inside Termux; `termux-shim.sh` is internal to `termux-sim`. `behavior-snapshot.ps1`, `sandbox-run.ps1`, `trace-run.ps1`, and `termux-sim.ps1` are launchers that need a POSIX shell; without one they exit 3 and say so.
- Windows PowerShell 5.1 has no `&&`, `||`, or `?:`: run commands separately. Pass forward slashes to POSIX tools. Its `>` and `Out-File` write UTF-16, so scripts let git or .NET write files.
- Git for Windows bundles `sh`, `bash`, `awk`, `sed` but may not put them on PATH; the `.ps1` scripts search its install directories. Tools detected outside system PATH require their full path or sandbox scripts, not bare commands.
- `host.env=termux` means you run inside the target: host-only assumptions do not apply.

## Gotchas
- Host `sh` may be bash or dash (`cap.syntax_posix` says which). Only `dash` or `busybox` reliably reject bashisms; Termux's `sh` is dash.
- dash older than 0.5.13 (Ubuntu 24.04 ships 0.5.12) rejects `set -o pipefail`; Termux's dash package is 0.5.13.5 in termux-packages master. Probe on the device instead of assuming.
- ShellCheck and shfmt versions differ between hosts and CI. A shfmt release with zsh support reads `.zsh` files as zsh from the extension (`cap.format_zsh=shfmt-diff-only`); an older one (3.8.0 in Ubuntu 24.04, `cap.format_zsh=manual`) parses them as bash and can rewrite zsh syntax wrongly. Any parser or printer flag (`-ln zsh`, `-i`) makes shfmt ignore `.editorconfig`, so run `shfmt -d FILE.zsh` with no flags.
- macOS and BSD userland differ from Termux's (`sed -i`, `date`, `readlink`, `stat` flags): results there are indicative.
- Exec bits do not survive Windows hosts or zip files: call scripts through their interpreter.
- Windows: `& .\x.ps1` fails with PSSecurityException ("not digitally signed") under the default execution policy or after a zip download. Use `powershell -NoProfile -ExecutionPolicy Bypass -File x.ps1` (per-file alternative: `Unblock-File`).
- `zsh` is usually absent on Windows: zsh files are then checked by heuristics only (`coverage=partial`); WSL or MSYS2 provide `zsh -n`.
