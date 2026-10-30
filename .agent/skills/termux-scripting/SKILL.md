---
name: termux-scripting
description: Writes, modifies, and hardens zsh, POSIX sh, and bash code for Termux - dialect choice, Termux-safe constructs, idempotent defensive structure, stream and logging rules for utilities versus wrappers versus CLI integrations, a cross-platform lint gate and formatter, and a sandbox and Termux-simulation test harness. Use for any *.sh, *.zsh, installer, utility, shell function, alias, or wrapper, and to make shell code portable, safer, faster, or lint-clean. Not for read-only audits (code-review), restructuring without behavior change (code-refactoring), or Termux config files (termux-customization).
---

# Termux scripting

Paths are relative to this skill directory. Run scripts through their interpreter (`sh x.sh` or `powershell -NoProfile -ExecutionPolicy Bypass -File x.ps1`). Runtime facts: skill `termux-environment`. Host tools missing: skill `platform-detection`.

## 1. Pick the dialect (facts first)
- Existing file: keep its dialect (shebang, else extension). Convert only when asked.
- New file: interactive config, functions, aliases, prompt, wrappers -> zsh module. Standalone script, installer, boot script, helper for minimal environments -> POSIX sh (Termux `sh` is dash). Use bash only when the project's scripts are bash (see `dialect.*` in repo-map) or arrays, associative arrays, or `[[ ]]` are truly needed.
- Never mix: a file with an `sh` shebang contains no bashisms; the lint gate enforces it.
- Shebang: follow the project's dominant form (`shebang` lines of repo-map). Without a convention use `#!/data/data/com.termux/files/usr/bin/<interpreter>` (needs no termux-exec); `/bin/...` and `/usr/bin/env` forms work only through termux-exec.
- Details: `references/dialects.md`, `references/posix-sh.md`, `references/zsh.md`.

## 2. Build checklist
- Start from `assets/templates/` (posix-script, zsh-module, command-wrapper, test-harness): replace the `NAME` and `TOOL` placeholders, keep banners exact-length, and add a comment only under the comment rule.
- `main "$@"` entry; single-purpose functions; libraries and modules do no work at source time.
- Fail fast: `set -eu` (sh/bash), `${1:-}` for optional arguments; validate arguments and required commands up front with a clear stderr message and a non-zero exit.
- Idempotent: a re-run changes nothing. Check state first; `mkdir -p`, `ln -sfn`, `grep -qxF line file || printf '%s\n' line >> file`; write via temp file in the same directory then `mv`; back up user files before overwriting; remove temp files with `trap ... EXIT INT TERM`.
- Quote every expansion; `--` before user-supplied operands; no `eval` of untrusted data; no `rm -rf` on a variable without a non-empty and prefix guard.
- Paths: `$HOME`, `$PREFIX`, `$TMPDIR`; never `/tmp`, `/usr`, `/etc`, `/bin`, `/home`. Scripts, state, and executables stay in `$HOME` or `$PREFIX`; shared storage is for data exchange only.
- `termux-*` API tools: guard with `command -v` and provide a fallback (they need the Termux:API app and the `termux-api` package).
- Declare then assign: `local x; x=$(cmd)` (a combined `local x=$(cmd)` hides the exit status).
- Performance: no forks in loops or in shell startup; prefer parameter expansion and builtins over `sed`/`awk`/`cut` for simple string work.

## 3. Output and logging
| Code kind | Output rule |
|---|---|
| Installer, general utility | the project's logger and prefix convention (`logui.*` in repo-map); default prefixes `[*] [+] [-] [!] [?]`, flat, lowercase, to stderr |
| Wrapper that shadows a system command (for example `sudo`, `ls`, `grep`) | mimic the native command exactly: wording, streams, exit codes; no prefixes, no restyling |
| Integration with an external CLI | pure data on stdout, plain messages on stderr, conventional exit codes; no prefixes |
Pipes stay clean: data on stdout, everything else on stderr (`>&2`). Identify wrappers and integrations by role (search definitions and call sites), not by file name. Restyling their messages is out of scope.

Comments: only for non-obvious reasons, Termux or Android constraints, workarounds, and hazards; never for what the code does. Section banners use exact-length hash borders (core policy).

## 4. Quality gate (run after every edit)
`sh scripts/lint-shell.sh [paths]` or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint-shell.ps1 [paths]`
- Format modified sh/bash files first: `sh scripts/format-shell.sh --write PATH...` (or the `.ps1` flavor). Without `--write` it prints the diff and exits 1 when files differ. It uses shfmt through `.editorconfig` with no style flags, skips files without an `.editorconfig`, and never rewrites zsh. `--out FILE` stores the diff; exit 3 means shfmt is missing (format by hand following `.editorconfig`).
- No paths = every shell-like file of the repository (agent directories and `.artifacts/` excluded). Output: `LEVEL file:line [CODE] message` and one `SUMMARY ... coverage=full|partial skipped=...` line. Options: `--dialect`, `--no-external`, `--strict`, `--max-per-rule`, `--root`, `--list` (print dialect and file only), `--out FILE` (write findings to a file and print only SUMMARY; use for more than about 200 lines, for example `.artifacts/lint/report.txt`).
- Uses ShellCheck (+ `.shellcheckrc`), shfmt (+ `.editorconfig`, only when one exists), dialect syntax checks, and heuristics from `scripts/patterns.tsv` (bashisms in sh, zsh pitfalls, FHS paths, banner borders, CRLF, log-prefix evidence). Missing tools give `SKIP` lines and `coverage=partial`: say so in the report.
- Heuristic hits are leads: confirm against the code. Suppress a confirmed false positive with a trailing `# lint-ignore: CODE`. Here-document bodies are skipped; `H001` means a delimiter never closed and later lines were not checked.
- ERROR must be fixed; WARN fixed or justified. ShellCheck info/style notes count as WARN (the project baseline is clean): judge by new findings in the files you changed, not by the repo total.
- `T003` (INFO) flags commands that a default Termux install lacks (`sudo`, `systemctl`, `lsb_release`, ...); `T005` (INFO) flags `command -v su`, which succeeds without root because Termux ships a `su` wrapper (test `su -c true` instead).
- `L002` (WARN) = a log prefix or logger call inside a function named like a system command or CLI integration (`scripts/wrapper-names.txt`; a trailing `*` matches a prefix). The standard list covers system commands; add the project's wrapper and integration names there (find them with repo-map definitions; do not guess). Remove the prefix and keep native output. `L001` (INFO) is evidence: confirm prefixed output exists only where the project's convention uses prefixes (default: installers and utilities).
- ShellCheck skips zsh by design. For `.zsh` files the gate prints an advisory `FMT` line with the shfmt hunk count, or a `SKIP shfmt-zsh` line when the installed shfmt has no zsh support (it would parse the file as bash). shfmt on zsh: run `shfmt -d FILE.zsh` with no flags (dialect from the extension, `.editorconfig` applied), review each hunk, never write: it can turn `$+commands[a-b]` into `$+commands[a - b]`. Match the existing zsh style by hand.
- Never pass shfmt style or parser flags (`-i`, `-ci`, `-ln`, ...): any flag makes it ignore `.editorconfig`.

## 5. Test
- `sh scripts/sandbox-run.sh --stub-termux --twice -- path/to/script [args]` runs a script in a Termux-like sandbox (fake `HOME`/`PREFIX`/`TMPDIR`, recorded `termux-*` stubs, cleared environment) and reports idempotency. `--stub NAME=EXIT:TEXT` fakes one command; `--seed SRC[:DEST]` pre-populates `HOME`; `--env NAME=VALUE` adds a variable; `--overlay DIR` copies a prepared tree in; `--keep` stores the sandbox under `.artifacts/sandbox/`. `sudo` and `doas` are always stubbed (exit 127). Literal `/data/data/com.termux` paths are not remapped.
- A script that reads Termux facts (`uname -o`, `getprop`, `id`, `su`, `pkg`, `dpkg`, storage) runs through `termux-environment/scripts/termux-sim.sh` instead (`--root` for root paths): same sandbox, plus stand-ins for those commands. Report such results as simulated.
- Sourced modules and libraries have no entry point: test them through a 3-line driver run in the sandbox (zsh: `source "${0:A:h}/mod.zsh"; fn args`; sh: `. "$(dirname "$0")/mod.sh"; fn args`; add `--dialect`).
- Tests: `assets/templates/test-harness.sh.tpl`, only when the change is risky or the project already has tests. Behavior-preserving changes: skill `code-refactoring` (`behavior-snapshot`).
- Real Termux behavior (permissions, termux-exec, Android, Termux:API) cannot be proven on a host. Use the Termux container (no Android runtime) or a device, and give the user exact commands for what remains.

## 6. Gotchas (tested in dash 0.5.12, busybox ash, bash 5.2, zsh 5.9 unless noted)
- dash rejects `[[ ]]`, arrays, `read -p`, `$'..'`, `${v//a/b}`, `source`, `function`, `<<<`, `&>`; `echo -e` prints `-e`.
- `echo "a\tb"` expands in dash and zsh but not in bash: use `printf '%s\n'`.
- `cmd | while read` loses variables in dash, busybox, and bash; zsh keeps them: use a temp file or here-document.
- `local x=$(cmd)` hides failure; `set -e` does not fire inside conditions or `&&`/`||` lists.
- `pipefail` is missing in dash 0.5.12 (POSIX.1-2024 adds it; dash 0.5.13 has it, and Termux's dash package is 0.5.13.5 in termux-packages master): probe with `(set -o pipefail) 2>/dev/null && set -o pipefail`; check the device's `dpkg -s dash`.
- dash 0.5.12 leaves `LINENO` empty.
- zsh: no word splitting of `$var`; arrays are 1-indexed (`${a[0]}` is empty); `read -p` is a coprocess (use `read 'v?prompt'`); `${!v}` unsupported (use `${(P)v}`); an unmatched glob is an error (use `(N)`); never name a variable `path`, `status`, `argv`, `commands`, ... (`local path=` breaks command lookup).
- `emulate -L zsh` first in reusable zsh functions.
- CRLF breaks shebangs (`bad interpreter`) and values: LF only.
- BSD (macOS host) and GNU utilities differ in `sed -i`, `date`, `readlink`, `stat`; verify flags on Termux (`pkg show coreutils`).
- `chmod` and `ln -s` fail inside shared storage; `/bin/sh` is Android's shell unless termux-exec intercepts.
- `command -v su` is true on a non-rooted Termux (a wrapper script); `su -c true` fails there. Keep root paths optional.
