---
name: code-review
description: Reviews code beyond the diff: reads whole files and callers, verifies every command, flag, function, and path exists, and ranks findings by severity. Use for review, audit, 'what changed', and before commit.
---

# Code review

Read-only: report findings, do not edit. A request to review and fix: report first, then fix only the findings that pass the finding gate (`termux-scripting` or `code-refactoring`); at high risk wait for the user's go.

## Modes
- Review: findings by severity and a verdict (`assets/review-report.md`).
- Change analysis ("what changed", "analyze the diff"): what changed, where, and why, without a verdict unless asked (`assets/change-analysis.md`).
  Both modes use the same evidence procedure.

## Evidence procedure
1. Scope: `git --no-pager status --short`. A clean tree, or a request about existing code (a file, a directory, the repository), has no diff: the scope is the files the user named, else the files listed by `lint-shell --list` (`termux-scripting`). Skip steps 2-4, read each file whole (step 5), and list the files in the coverage line.
2. Collect the diff to disk: `sh .agents/skills/code-review/scripts/diff-collect.sh` (or `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/code-review/scripts/diff-collect.ps1`). Options: `--staged`, `--unstaged`, `--range A..B`, `--include-agent`, `--out DIR`, `--chunk N`. Default scope: working tree vs HEAD plus untracked files, without `.agent`, `.agents`, and `.artifacts` (agent tooling and its output are not project code).
3. Check the script output:
   - It ends with `END`. No `END` means the terminal cut it: read `MANIFEST.tsv` from disk.
   - `verify=ok`. `verify=mismatch` (exit 1) means a patch file is incomplete or git output changed: re-run; if it persists, report it and read the changed files directly.
   - `excluded=N` means the default filter left out N paths under `.agent` or `.agents`; `files=0` next to it is not "nothing changed". Add `--include-agent` when the task edits agent files.
4. Read every part file completely with the file viewer, in the `ranges` the script printed (at most 250 lines each). If the viewer returns fewer lines than requested, split the range. Note each range as you read it; the coverage line of step 9 reports them. Read `skipped` manifest rows directly, in ranges.
5. Read each changed (or in-scope) file whole in its current state, not only the hunks. Read callers of every changed function (search by name), every file that sources a changed library with its shebang, the project config (`.editorconfig`, `.shellcheckrc`), and the docs and `--help` text that describe the changed behavior.
6. Reference check: the diff shows what changed, not whether what it uses exists. For each command, option, function, variable, file, URL, package, and version the changed code uses or adds, find the proof now:
   - Project function, variable, or file: search for its definition; for a sourced one, check that the caller sources it before use.
   - Host or Termux command and its options: `command -v` plus its `--help` or manual on that platform (Termux commands: `termux-environment`, or the package in termux-packages). An option known only from memory is unverified.
   - Library API, URL, package name, or version: a primary source, cited with its URL.
   - Claims in comments, help text, docs, and the commit message ("idempotent", "works without root"): run the code through a harness (`sandbox-run`, `trace-run`), or on the device when the user granted SSH (`termux-environment`); otherwise mark the claim UNVERIFIED.
     A reference without proof is a major finding when the code depends on it (unverified assumption), else an unverified lead.
7. Run the lint gate (`termux-scripting` `lint-shell`) on the changed files; read every ERROR and WARN and the SUMMARY line.
8. Review: Stage A, spec: does the change do exactly what was asked? Map every hunk to a criterion or a finding; an unmapped hunk is extra behavior. Stage B, quality: apply the checklist. Each finding must pass the finding gate and carries a concrete fix; mark device-only items UNVERIFIED.
   Change analysis: per file, state what changed (code facts), where (function, file:line), and the behavior effect. Take intent only from the request, commit messages (`git --no-pager log -n 10 --format="%h %s%n%b"`), or code comments; mark inferred intent as inferred.
9. Report with the template. Include the coverage line: parts and line counts read in full, files read in full, skipped files, references checked and unverified.

`diff-collect` writes `tracked.diff`, `untracked.diff`, and `MANIFEST.tsv` under `.artifacts/diff` at the project root (inside the workspace). If the file viewer cannot open that path, pass `--out` with a directory inside the workspace.

## Finding gate
An item is a finding only when all three hold; anything else goes under "Unverified leads", with no severity and no edit.
1. Fact: `path:line` and what the code does.
2. Evidence: a failing reproducer run through a harness (`systematic-debugging` step 2, with shell and version), or the documented rule or primary source it violates, cited; for a non-behavioral defect (dead code, an unused variable) the deterministic check named in the core policy, and the finding is minor or nit. Lint INFO, style notes, and "could fail" are not evidence.
3. Intent check (core policy): no recorded reason covers the code, or new evidence contradicts it.
   No findings is a valid verdict: report it with the coverage line.

## Severity
- blocker: wrong behavior, data loss, security hole, native-behavior change in wrapper or external-CLI integration code (wording, stream, exit code, added prefix), broken Termux compatibility, lint ERROR.
- major: missing idempotency or input validation, wrong streams, prefix misuse, unquoted expansions, unverified assumption in code.
- minor: style or maintainability with limited impact; WARN left unjustified.
- nit: optional polish.

## Checklist
- References: every command, option, function, path, and API the code uses exists and behaves as the code assumes (step 6).
- Correctness: requested behavior, meaningful exit codes, edge cases (empty input, spaces in names, missing tools, re-run).
- Termux: no FHS paths; `$PREFIX`/`$HOME`/`$TMPDIR`; shebang follows the project; no exec/chmod/symlink in shared storage; `termux-*` guarded; no root assumptions.
- Dialect: no bashisms in sh, no bash habits in zsh; `local x; x=$(...)`; `pipefail` probed in sh.
- Safety: quoted expansions; `--` before operands; no `eval` of untrusted data; guarded `rm -rf`; `mktemp` plus trap; no secrets in code or logs; downloads verified or user-approved; no silent overwrite of user files.
- Idempotency and fail-fast: a re-run is a no-op; arguments and dependencies validated first; errors stop the run with a stderr message.
- Streams and logging: data on stdout, logs and errors on stderr; prefixes only where the project's convention uses them (default: installers and general utilities; lint `L002` is a violation, check `L001` hits); wrappers and external-CLI integrations keep native output; identify them by role, not file name. Log messages stay within 36 characters; longer text is split into several log calls (lint `L003`).
- Comments: none that restate the code and none numbered (`C002`); banner borders exact-length.
- Style: ShellCheck and shfmt clean under the project configs; naming consistent with neighbors.
- Over-engineering: abstraction, option, dependency, or config the goal does not need; code for hypothetical futures; logic an existing helper already covers (search before approving).
- Performance: forks in loops, work at source time, shell-startup cost.
- Draft commit message follows the core policy format: subject, paragraph body.

## Gotchas
- `git diff` in the terminal can be cut by a pager or output limit; `--stat` abbreviates long paths. `diff-collect` avoids both and checks the result against `--numstat`.
- `git diff` omits untracked files; `diff-collect` adds them. Renames appear as delete plus add (`--no-renames`).
- A clean lint does not prove correctness: read the logic. Reading it can also find nothing wrong: report that.
- Heuristic hits (every INFO, `T001`, `Z004`) can be false positives: confirm in context before reporting; INFO alone never justifies an edit.
- Review the code and the diff on disk, not the author's description: a description or commit message is a claim to verify (step 6).
- Findings outside the diff are valid when the change breaks them (callers, docs, consumers) or when the user asked for a review of existing code; do not demand unrelated changes.
- One clear blocker outweighs ten nits.
