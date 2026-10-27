---
name: code-review
description: Read-only review and change analysis of shell and Termux code with complete diff coverage. Collects the full diff to disk with no pager or truncation, verifies it against git statistics, reads every changed file, then reports severity-ranked findings (review) or a per-file summary of what changed (analysis). Use for review, audit, check, "is this correct", pre-commit checks, and for questions such as "what changed in X", "analyze the diff", "explain this commit". Mandatory review stage after any code change. To change code use termux-scripting or code-refactoring.
---

# Code review

Paths are relative to this skill directory. Read-only: report findings, do not edit.

Research authority: search the web yourself when docs or dependency facts are missing or stale (primary sources first: Termux wiki, termux-packages, termux-app, Android and shell manuals); cite URLs; never guess.

## Modes
- Review: findings by severity and a verdict (`assets/review-report.md`).
- Change analysis ("what changed", "analyze the diff"): what changed, where, and why, without a verdict unless asked (`assets/change-analysis.md`).
Both modes use the same evidence procedure.

## Evidence procedure
1. Scope: `git --no-pager status --short`.
2. Collect the diff to disk: `sh scripts/diff-collect.sh` (or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/diff-collect.ps1`). Options: `--staged`, `--unstaged`, `--range A..B`, `--include-agent`, `--out DIR`, `--chunk N`. Default scope: working tree vs HEAD plus untracked files, without `.agent` and `.agents` (agent tooling is not project code).
3. Check the script output:
   - It ends with `END`. No `END` means the terminal cut it: read `MANIFEST.tsv` from disk.
   - `verify=ok`. `verify=mismatch` (exit 1) means a patch file is incomplete or git output changed: re-run; if it persists, report it and read the changed files directly.
4. Read every part file completely with the file viewer, in the `ranges` the script printed (at most 250 lines each). If the viewer returns fewer lines than requested, split the range. Keep a ledger: part file, ranges read, total lines. Read `skipped` manifest rows directly, in ranges.
5. Read each changed file whole in its current state, not only the hunks. Read callers of every changed function (search by name) and the project config (`.editorconfig`, `.shellcheckrc`).
6. Run the lint gate (`termux-scripting` `lint-shell`) on the changed files; read every ERROR and WARN and the SUMMARY line.
7. Review: Stage A, spec: does the diff do exactly what was asked? List missing and extra behavior. Stage B, quality: apply the checklist. Each finding needs file:line, the observed fact, and a concrete fix; mark device-only items UNVERIFIED.
   Change analysis: per file, state what changed (code facts), where (function, file:line), and the behavior effect. Take intent only from the request, commit subjects (`git --no-pager log -n 10 --format="%h %s"`), or code comments; mark inferred intent as inferred.
8. Report with the template. Include the coverage line: parts and line counts read in full, files read in full, skipped files.

`diff-collect` writes `tracked.diff`, `untracked.diff`, and `MANIFEST.tsv` under `.termux-agent/diff` (inside the workspace). If the file viewer cannot open that path, pass `--out` with a directory inside the workspace.

## Severity
- blocker: wrong behavior, data loss, security hole, native-behavior change in wrapper or CLI-integration code (wording, stream, exit code, added prefix), broken Termux compatibility, lint ERROR.
- major: missing idempotency or input validation, wrong streams, prefix misuse, unquoted expansions, unverified assumption in code.
- minor: style or maintainability with limited impact; WARN left unjustified.
- nit: optional polish.

## Checklist
- Correctness: requested behavior, meaningful exit codes, edge cases (empty input, spaces in names, missing tools, re-run).
- Termux: no FHS paths; `$PREFIX`/`$HOME`/`$TMPDIR`; shebang follows the project; no exec/chmod/symlink in shared storage; `termux-*` guarded; no root assumptions.
- Dialect: no bashisms in sh, no bash habits in zsh; `local x; x=$(...)`; `pipefail` probed in sh.
- Safety: quoted expansions; `--` before operands; no `eval` of untrusted data; guarded `rm -rf`; `mktemp` plus trap; no secrets in code or logs; downloads verified or user-approved; no silent overwrite of user files.
- Idempotency and fail-fast: a re-run is a no-op; arguments and dependencies validated first; errors stop the run with a stderr message.
- Streams and logging: data on stdout, logs and errors on stderr; prefixes only in installers and general utilities (lint `L002` is a violation; check `L001` hits); wrappers and CLI integrations keep native output; identify them by role, not file name.
- Comments: none that restate the code; banner borders exact-length.
- Style: ShellCheck and shfmt clean under the project configs; naming consistent with neighbors.
- Over-engineering: abstraction, option, dependency, or config the goal does not need; code for hypothetical futures; logic an existing helper already covers (search before approving).
- Performance: forks in loops, work at source time, shell-startup cost.
- Draft commit message follows the core policy format.

## Gotchas
- `git diff` in the terminal can be cut by a pager or output limit; `--stat` abbreviates long paths. `diff-collect` avoids both and checks the result against `--numstat`.
- `git diff` omits untracked files; `diff-collect` adds them. Renames appear as delete plus add (`--no-renames`).
- A clean lint does not prove correctness: read the logic.
- Heuristic hits (`T001`, `Z004`) can be false positives: confirm in context before reporting.
- Review the diff on disk, not the author's description.
- Do not demand changes outside the diff unless the diff breaks them.
- One clear blocker outweighs ten nits.
