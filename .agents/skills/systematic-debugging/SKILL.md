---
name: systematic-debugging
description: Finds root causes of shell and Termux failures: capture, reproduce, localize, hypothesize, minimal fix, verify. Use for errors, crashes, wrong output, hangs, 'not working', and 'command not found'.
---

# Systematic debugging

Run `platform-detection` first; runtime facts: skill `termux-environment`.

## Workflow
1. Capture: exact command, environment (host or Termux, shell, dialect), expected vs actual, full error text, exit status. Ask the user only for what you cannot obtain yourself (device output).
2. Reproduce on the host when possible: `sh .agents/skills/systematic-debugging/scripts/trace-run.sh --shell <dialect> -- script args`, or the sandbox (`sandbox-run` in `termux-scripting`). When the failure depends on Termux facts (`uname -o`, `su`, `getprop`, `pkg`, shared storage, a missing command), reproduce it on the device over SSH (`termux-environment`, Device checks over SSH). Without SSH access, say that it fails only on a device and prepare device commands. A reproducer is a file run through a harness, with the shell and its version recorded (`termux-scripting` section 5); a result that contradicts the manual of that version points at the reproducer first (wrong shell, altered quotes).
3. Localize: lint gate and `-n` for syntax; trace for flow (full logs stay on disk, read them in ranges); minimal reproducer; `git --no-pager log -S'text' --format='%h %s%n%b'` or `git bisect` for regressions (the reason for a line is usually in the commit body); compare dialects (dash, bash, zsh) when behavior differs.
4. Hypothesize: at most 3, ranked; test the cheapest first; change one thing at a time. Check `references/termux-error-patterns.md` for known Termux symptoms.
5. State the root cause in one sentence with evidence (file:line, command output). No fix before this step.
6. Fix: smallest change at the root cause; keep style; no refactor or drive-by edits. Wrapper and CLI-integration code keeps native wording, streams, and exit codes. Run the intent check (core policy) before changing a line that looks deliberate.
7. Verify: the reproducer passes; lint gate clean; re-run for idempotency; one neighboring case for regressions. Add a regression test only when the project has tests or the bug was subtle (`termux-scripting` test harness).
8. Review with `code-review`, then report with `assets/bug-report.md` and the final report format of `using-termux-skills`.

## trace-run
`sh .agents/skills/systematic-debugging/scripts/trace-run.sh [--shell dash|busybox|sh|bash|zsh] [--tail N] [--timeout S] [--out DIR] -- SCRIPT [ARGS]` (or `.agents/skills/systematic-debugging/scripts/trace-run.ps1`, a launcher that needs a POSIX shell). It runs under xtrace, keeps `$0`, arguments, and the exit status, and prints bounded tails; full logs stay in `.artifacts/trace/<UTC time>/` at the project root (the printed directory), where file viewers can open them. bash and zsh traces carry file:line; busybox ash, and dash or sh when the shell sets `LINENO` (dash 0.5.13.5 does, 0.5.12 does not), carry the line number only. `--out DIR` may be any directory; under `.artifacts/` the script also creates `.artifacts/.gitignore`. `HOME`, `PREFIX`, and `TMPDIR` point to throwaway directories under that output directory; it is not a sandbox, so host commands and paths still work.

## Toolbox
- Syntax: `dash -n f`, `bash -n f`, `zsh -n f`. Flow: `sh -x`, `bash -x`, `zsh -x`.
- Isolation: `env -i PATH="$PATH" sh f`, `bash --noprofile --norc`, `zsh -f`.
- zsh startup problems: `time zsh -i -c exit`, `zprof`, `zsh -x -i -c exit 2> trace.log`.
- Resolution: `command -v x`, `type x`, zsh `whence -v x`, `echo "$PATH"`.
- Dialect comparison: `sandbox-run --dialect posix|bash|zsh`.

## Gotchas
- Fix the cause, not the symptom: a `|| true` or `2> /dev/null` added to pass a check hides bugs. An existing one may be deliberate (expected non-zero status, optional tool): run the intent check before removing it.
- A bug that vanishes under `-x` points to timing, buffering, or an unquoted expansion.
- Wrapper bugs: compare with the native command's output and exit code; do not add prefixes.
- `local x=$(cmd)` and pipelines hide failures: check `$?` separately.
- Host vs device differences: dialect (dash vs bash), GNU vs BSD flags, FHS paths, shared-storage limits, missing Termux:API, Android killing the process.
- Do not run destructive commands on the user's device to reproduce; ask first. Device runs go through the SSH recipe of `termux-environment`, which leaves no files behind.
