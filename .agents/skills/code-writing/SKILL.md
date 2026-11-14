---
name: code-writing
description: Writes, hardens, and restructures zsh, sh, and bash for Termux. Use when creating, editing, or refactoring scripts, wrappers, and shell modules. Not for audits.
---

# Code writing

Script invocation: core policy. Runtime facts: skill `termux-environment`. Host tools missing: skill `platform-detection`.

Use for new or changed shell code (scripts, functions, wrappers, installers, aliases) and for behavior-preserving cleanup (rename, extract, move, split, merge, deduplicate, simplify). Reviews belong to `code-review`, failures to `systematic-debugging`, Termux configuration files to `termux-customization`.

## Flow
Starts once the plan lists the requirements and checks (`using-termux-skills`) and `platform-detection` and `termux-environment` have fixed the host and runtime constraints. Finished when the code and the test harness the plan names exist and the unit checks pass: formatted, lint gate with no ERROR (WARN fixed or justified), harness green. Hands off to `code-review` (and `check-termux-config` for `.properties` files); after review passes, it runs the plan's behavior checks with `sandbox-run`. A failing unit or behavior check goes to `systematic-debugging`; review findings come back here.

## Dialect
- Existing file: keep its dialect (shebang, else extension). Convert only when asked. A sourced library must be valid in every file that sources it: search for its `source`/`.` lines and read each caller's shebang before judging a construct.
- New file: interactive config, functions, aliases, prompt, wrappers -> zsh module. Standalone script, installer, boot script, helper for minimal environments -> POSIX sh (Termux `sh` is dash). Use bash only when the project's scripts are bash (see `dialect.*` in repo-map) or arrays, associative arrays, or `[[ ]]` are truly needed.
- Never mix: a file with an `sh` shebang contains no bashisms; the lint gate enforces it.
- Shebang: follow the project's dominant form (`shebang` lines of repo-map). Without a convention use `#!/data/data/com.termux/files/usr/bin/<interpreter>` (needs no termux-exec); `/bin/...` and `/usr/bin/env` forms work only through termux-exec.
- Details: `references/dialects.md`, `references/posix-sh.md`, `references/zsh.md`.

## Build checklist
- Match structure from existing files in the repo (or checklist below); keep banners exact-length, and add a comment only under the comment rule.
- `main "$@"` entry; single-purpose functions; libraries and modules do no work at source time.
- Fail fast: `set -eu` (sh/bash), `${1:-}` for optional arguments; validate arguments and required commands up front with a clear stderr message and a non-zero exit.
- Idempotent: a re-run changes nothing. Check state first; `mkdir -p`, `ln -sfn`, `grep -qxF line file || printf '%s\n' line >> file`; write via temp file in the same directory then `mv`; back up user files before overwriting; remove temp files in an `EXIT` trap and map signals with `trap 'exit 130' INT` and `trap 'exit 143' TERM` (a cleanup-only trap on `INT TERM` lets the script resume after the signal and loses its status).
- Quote every expansion; `--` before user-supplied operands; no `eval` of untrusted data; no `rm -rf` on a variable without a non-empty and prefix guard.
- Paths: `$HOME`, `$PREFIX`, `$TMPDIR`; never `/tmp`, `/usr`, `/etc`, `/bin`, `/home`. Scripts, state, and executables stay in `$HOME` or `$PREFIX`; shared storage is for data exchange only.
- `termux-*` API tools: guard with `command -v` and provide a fallback (they need the Termux:API app and the `termux-api` package).
- Declare then assign: `local x; x=$(cmd)` (a combined `local x=$(cmd)` hides the exit status).
- Performance: no forks in loops or in shell startup; prefer parameter expansion and builtins over `sed`/`awk`/`cut` for simple string work.

## Output and logging
Output contract by code role, log text limit, and comment rule: core policy. Find the project's logger and prefix convention with `logui.*` in repo-map. Identify wrappers and integrations by role (search definitions and call sites), not by file name; `scripts/wrapper-names.txt` feeds lint `L002`. Data on stdout, everything else on stderr (`>&2`).

## Quality gate (run after every edit)
`sh .agents/skills/code-writing/scripts/lint-shell.sh [paths]` or `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/code-writing/scripts/lint-shell.ps1 [paths]`
- Format modified sh/bash files first: `sh .agents/skills/code-writing/scripts/format-shell.sh --write PATH...` (or the `.ps1` flavor). Without `--write` it prints the diff and exits 1 when files differ. It uses shfmt through `.editorconfig` with no style or parser flags (any flag makes shfmt ignore `.editorconfig`), skips files without an `.editorconfig`, and never rewrites zsh. `--out FILE` stores the diff; exit 3 means shfmt is missing (format by hand following `.editorconfig`).
- No paths = every shell-like file of the repository (agent directories and `.artifacts/` excluded). Output: `LEVEL file:line [CODE] message` and one `SUMMARY ... coverage=full|partial skipped=...` line. Options: `--dialect`, `--no-external`, `--strict`, `--max-per-rule`, `--root`, `--list` (print dialect and file only), `--out FILE` (write findings to a file and print only SUMMARY; use for more than about 200 lines, for example `.artifacts/lint/report.txt`).
- Uses ShellCheck (+ `.shellcheckrc`), shfmt (+ `.editorconfig`, only when one exists), dialect syntax checks, and heuristics from `scripts/patterns.tsv` (bashisms in sh, zsh pitfalls, FHS paths, banner borders, CRLF, log-prefix evidence) plus built-in checks for numbered comments and log message length. Missing tools give `SKIP` lines and `coverage=partial`: say so in the report.
- Heuristic hits are leads: confirm against the code. Suppress a confirmed false positive with a trailing `# lint-ignore: CODE`. Here-document bodies are skipped; `H001` means a delimiter never closed and later lines were not checked.
- ERROR must be fixed; WARN fixed or justified. ShellCheck info/style notes count as WARN: judge by new findings in the files you changed, not by the repository total. `INFO` lines (heuristics and advisories) are leads: confirm a failure or a violated rule before editing, and never edit only to silence one.
- `T002` (INFO) flags a literal Termux path; a shebang and a `${PREFIX:-...}` default are legitimate uses. `T003` (INFO) flags commands that a default Termux install lacks (`sudo`, `systemctl`, `lsb_release`, ...); `T005` (INFO) flags `command -v su`, which succeeds without root because Termux ships a `su` wrapper (test `su -c true` instead).
- `L002` (WARN) = a log prefix or logger call inside a function named like a system command or CLI integration (`scripts/wrapper-names.txt`; a trailing `*` matches a prefix). The standard list covers system commands; add the project's wrapper and integration names there (find them with repo-map definitions; do not guess). Remove the prefix and keep native output. `L001` (INFO) is evidence: confirm prefixed output exists only where the project's convention uses prefixes (default: installers and utilities).
- `C002` (WARN) flags a full-line comment that starts with a number or `Step N` (`# 1.`, `# 2)`, `# Step 3:`). `L003` (WARN) flags a `log_*` message of more than 36 characters (the text between the quotes on that line; multi-line messages and function definitions are skipped). Rewrite the comment, or split the message into several log calls (core policy).
- ShellCheck skips zsh by design. For `.zsh` files the gate prints an advisory `FMT` line with the shfmt hunk count, or a `SKIP shfmt-zsh` line when the installed shfmt has no zsh support (it would parse the file as bash). shfmt on zsh: run `shfmt -d FILE.zsh` (no flags; dialect from the extension, `.editorconfig` applied), review each hunk, never write: it can turn `$+commands[a-b]` into `$+commands[a - b]`. Match the existing zsh style by hand.

## Test
- Run a script only through a harness, never directly on the host. `sh .agents/skills/code-writing/scripts/sandbox-run.sh --stub-termux --twice -- path/to/script [args]` runs it with fake `HOME`/`PREFIX`/`TMPDIR`, recorded `termux-*` stubs, and a cleared environment, and reports idempotency (the second run must exit with the same status and leave the files, symlinks, and directories under `HOME` and `PREFIX` unchanged). It redirects the environment only: the working directory stays the caller's (relative writes land there), and absolute host paths, the network, and host commands (`rm`, `git`, `apt-get`) still work, so read the script for destructive commands first. `--stub NAME=EXIT:TEXT` fakes one command; `--seed SRC[:DEST]` pre-populates `HOME`; `--env NAME=VALUE` adds a variable (`@SANDBOX@` in VALUE becomes the sandbox directory); `--timeout S` bounds the run (default 60); `--keep` stores the sandbox under `.artifacts/sandbox/`. `sudo` and `doas` are stubbed (exit 127) unless `--stub` names them. Literal `/data/data/com.termux` paths are not remapped. The sandbox sets `TERMUX_VERSION=sandbox`; a script that detects Termux through `uname -o` or `getprop` takes its host path there. The report lists at most 40 stub calls and 40 files and says how many more exist.
- Facts that only the device shows (`uname -o`, `getprop`, `id`, `su`, `pkg`, `dpkg`, storage, termux-exec) are not reproduced by the sandbox. Check them on the device (`termux-environment`, Device checks over SSH) or list them as not verified.
- Sourced modules and libraries have no entry point: test them through a 3-line driver run in the sandbox (zsh: `source "${0:A:h}/mod.zsh"; fn args`; sh: `. "$(dirname "$0")/mod.sh"; fn args`; add `--dialect`).
- Snippets and reproducers are files: write them under `.artifacts/temp/` and run `-- FILE` through the harness (quote handling differs by host shell: `platform-detection`). Record the shell and its version (`$BASH_VERSION`, `zsh --version`).
- Tests: write a test script under `.artifacts/temp/`, only when the change is risky or the project already has tests. Behavior-preserving cleanup: Structural cleanup below.
- Real Termux behavior (permissions, termux-exec, Android, Termux:API) cannot be proven on a host. Use the user's device over SSH (`termux-environment`, Device checks over SSH) or the Termux container (no Android runtime), and give the user exact commands for what remains.

## Structural cleanup (behavior unchanged)
Rename, extract, inline, move, split, merge, deduplicate, or simplify with behavior fixed: same stdout, stderr, exit codes, files written, environment variables set, and names defined (functions, aliases, variables, hooks, `source` order). A change to any of them is a feature or a fix, so it is a separate task.
- Before the first edit, run the checks that will prove sameness and keep their output under `.artifacts/temp/`: `git --no-pager status --short` (unrelated edits are listed, not mixed in), the lint gate on the files in scope, and a harness or `sandbox-run` case for each public command, function, and wrapper (normal use, no arguments, invalid input, `--help`). Cases are deterministic: no dates, process ids, random values, or network. Behavior only a device shows stays unverified; give the user the commands.
- One kind of change per step, small enough to review and revert alone, with no fixes, renames, or style edits outside the declared scope. After each step rerun the same commands: lint shows no finding the baseline lacked, and every case output is identical to the baseline. Fix or revert a failing step before the next one.
- Find code by searching definitions (`def` in repo-map, `grep`), not by assumed file names. After a rename or move, search the whole repository for the old name (code, docs, completions, installers). User-facing commands, aliases, and environment variables are interface: rename them only with the user's approval.
- Moves and splits: move code verbatim in one step and edit it in a later one; in the `diff-collect` output the deleted and added blocks are identical apart from planned edits. Each moved definition exists exactly once afterwards. A new file is loaded by the project's existing mechanism at a position that keeps the original definition order and source-time effects (aliases, `setopt`, hooks, `compdef`, traps), and is named after its neighbors. When shell startup code moves, compare `time zsh -i -c exit` before and after.
- Wrapper and external-CLI integration code keeps its user-visible text (casing and punctuation included), streams, and exit codes, and gets no prefixes; it can move.
- A line search cannot see dynamic definitions (`eval`, generated names, aliases built at runtime): add a sandbox case that prints what is defined after sourcing (bash `declare -F`; zsh `print -rl -- ${(ko)functions}`). Merging similar functions changes edge-case behavior: run both on those inputs first. Remove dead code only when a repository search shows no use and the user asked for it. After an intentional behavior change the baseline is stale: record a new one in a separate task.

## Gotchas (tested in dash 0.5.12 and 0.5.13.5, busybox ash 1.36.1, bash 5.2, zsh 5.9 unless noted)
- dash: arrays, `<<<`, `<(...)`, `function f {}` are parse errors; `[[ ]]`, `${v//a/b}`, `source`, `local -r` fail at run time; `cmd &> f` runs `cmd` in the background and creates an empty `f`; `echo -e` prints `-e`; `$'..'` is literal text in 0.5.12 and expanded in 0.5.13.5; `read -p` is accepted. `dash -n` catches only the parse errors.
- `echo "a\tb"` expands in dash and zsh but not in bash: use `printf '%s\n'`.
- bash: `"${a[@]}"` of an empty array under `set -u` is an error before 4.4 (4.3.0 tested) and valid from 4.4 (4.4.18, 5.2 tested); Termux ships bash 5.3. `${v,,}` and `${v^^}` work in bash only (zsh: `${(L)v}` or `${v:l}`; dash and busybox: `bad substitution`).
- `cmd | while read` loses variables in dash, busybox, and bash; zsh keeps them: use a temp file or here-document.
- `local x=$(cmd)` hides failure; `set -e` does not fire inside conditions or `&&`/`||` lists.
- `pipefail` is missing in dash 0.5.12 and present in 0.5.13.5, the version in termux-packages master (POSIX.1-2024 adds it): probe with `(set -o pipefail) 2>/dev/null && set -o pipefail`; check the device's `dpkg -s dash`. `LINENO` is empty in 0.5.12 and set in 0.5.13.5.
- zsh: no word splitting of `$var`; arrays are 1-indexed (`${a[0]}` is empty); `read -p` is a coprocess (use `read 'v?prompt'`); `${!v}` unsupported (use `${(P)v}`); an unmatched glob is an error (use `(N)`); never name a variable `path`, `status`, `argv`, `commands`, ... (`local path=` breaks command lookup).
- `emulate -L zsh` first in reusable zsh functions.
- CRLF breaks shebangs (`bad interpreter`) and values: LF only.
- BSD (macOS host) and GNU utilities differ in `sed -i`, `date`, `readlink`, `stat`; verify flags on Termux (`pkg show coreutils`).
- `chmod` and `ln -s` fail inside shared storage; `/bin/sh` is Android's shell unless termux-exec intercepts.
- `command -v su` is true on a non-rooted Termux (a wrapper script); `su -c true` fails there. Keep root paths optional.
