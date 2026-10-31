---
name: platform-detection
description: Detects the development host (Linux, macOS, Windows, WSL, Git Bash, MSYS), its package manager, and the full path of each available tool (ShellCheck, shfmt, dash, bash, zsh, git, PowerShell), and selects fallbacks for missing tools. Use before the first host command of a conversation and again when a host command fails with "not found", because a bare tool name can be absent from PATH while the tool exists (Git for Windows, MSYS2). Covers host tools only; a missing Termux command belongs to systematic-debugging or termux-environment.
---

# Platform detection

The host is where code is edited and checked; the target is Termux. Do not assume host OS, shell, or tools. Commands in this file run from the project root.

## Steps
1. Run the detector with no options:
   - POSIX shell present (`uname -s` works: Linux, macOS, WSL, Git Bash, MSYS, Cygwin): `sh .agents/skills/platform-detection/scripts/detect-platform.sh`
   - Windows PowerShell or cmd (`uname` not found): `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/platform-detection/scripts/detect-platform.ps1`; with PowerShell 7: `pwsh -NoProfile -File .agents/skills/platform-detection/scripts/detect-platform.ps1`
   `--brief` prints no `tool.NAME` paths: use it only to check availability, never to locate a tool.
2. Read the `key=value` output. `tool.NAME` is the command: call a host tool by that full path, never by its bare name (PowerShell: `& 'C:\Program Files\Git\usr\bin\bash.exe' args`; quote paths with spaces). `cap.*` names a provider, not a command: run the matching `tool.*` path.
3. The output is a snapshot, not memory. When a path, flag, or version is not visible in the current context (long session, checkpoint summary), or a tool fails with "not found", run the detector again. It is read-only and fast.
4. For each step you need, read `cap.*` (best provider, or the fallback). Order and coverage effects: `references/fallback-matrix.md`.
5. Missing tool: use the fallback; do not stop. Report which checks ran with reduced coverage.
6. `hint.*` lines are suggestions. Offer them only if the user wants the tool; do not install system packages without approval; verify package ids with the package manager first.

## Verify the tools on this host
`sh .agents/skills/platform-detection/scripts/selftest.sh` (and `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/platform-detection/scripts/selftest.ps1`) builds a throwaway repository, runs each skill tool once, and prints PASS, FAIL, or SKIP per tool plus `SELFTEST pass=N fail=N skip=N`. Run it once on a new host, after installing or updating a tool, or when a script behaves unexpectedly. A SKIP names a missing prerequisite; a FAIL is a defect on this host: report it with the printed lines.

## Output keys
`host.os` linux|macos|windows|android; `host.env` native|wsl|git-bash|msys|cygwin|termux; `host.arch`; `host.pkgmgr`; `tool.NAME` full path or `-` (`--brief`: one `tool.missing` line, no paths); `ver.shellcheck`, `ver.shfmt`; `cap.NAME` provider or `none`; `hint.NAME`; `run.scripts` sh|ps1. `--tools a,b` probes extra tools.

## Host command rules
- Every host script exists as `.sh` (needs a POSIX shell) and `.ps1` (Windows PowerShell 5.1+ or PowerShell 7+) with the same options, output, and exit codes. Exceptions: `device-facts.sh` runs inside Termux; `termux-shim.sh` is internal to `termux-sim`. `behavior-snapshot.ps1`, `sandbox-run.ps1`, `trace-run.ps1`, and `termux-sim.ps1` are launchers that need a POSIX shell; without one they exit 3 and say so.
- Windows PowerShell 5.1 has no `&&`, `||`, or `?:`: run commands separately. Pass forward slashes to POSIX tools. Its `>` and `Out-File` write UTF-16, so scripts let git or .NET write files.
- Git for Windows bundles `sh`, `bash`, `awk`, `sed` but may not put them on PATH; the `.ps1` scripts search its install directories, and `tool.*` prints the path they found.
- `host.env=termux` means you run inside the target: host-only assumptions do not apply.

## Gotchas
- Host `sh` may be bash or dash (`cap.syntax_posix` says which); Termux's `sh` is dash. `dash -n` reports parse errors only: arrays, `<<<`, `<(...)`, `|&`, and `function f {}` fail it, while `[[ ]]`, `${v//a/b}`, `source`, `$'..'`, `&>`, `read -p`, and `pipefail` pass it (tested in dash 0.5.12 and 0.5.13.5). The busybox ash 1.36.1 build tested here also accepts several of those. Bashisms are caught by ShellCheck `-s sh` (SC3xxx), the lint heuristics, and by running the code under dash in `sandbox-run`.
- dash 0.5.12 (Ubuntu 24.04) rejects `set -o pipefail`; 0.5.13.5, the version in termux-packages master, accepts it (both tested). Probe on the device instead of assuming.
- ShellCheck and shfmt versions differ between hosts and CI. A shfmt release with zsh support reads `.zsh` files as zsh from the extension (`cap.format_zsh=shfmt-diff-only`); an older one (3.8.0 in Ubuntu 24.04, `cap.format_zsh=manual`) parses them as bash and can rewrite zsh syntax wrongly. Any parser or printer flag (`-ln zsh`, `-i`) makes shfmt ignore `.editorconfig`, so run `shfmt -d FILE.zsh` with no flags.
- macOS and BSD userland differ from Termux's (`sed -i`, `date`, `readlink`, `stat` flags): results there are indicative.
- Exec bits do not survive Windows hosts or zip files: call scripts through their interpreter.
- Windows: `& .\x.ps1` fails with PSSecurityException ("not digitally signed") under the default execution policy or after a zip download. Use `powershell -NoProfile -ExecutionPolicy Bypass -File x.ps1` (per-file alternative: `Unblock-File`).
- `zsh` is usually absent on Windows: zsh files are then checked by heuristics only (`coverage=partial`); WSL or MSYS2 provide `zsh -n`.
