---
name: code-refactoring
description: Restructures shell and Termux code without changing behavior - rename, extract, inline, move, split or merge files, remove duplication, simplify. Captures a baseline (lint, definition index, behavior snapshot), applies one small step at a time, and compares after each step; wrapper and CLI-integration output stays native. Use for refactor, restructure, clean up, split a large file, rename, deduplicate, reorganize modules. Behavior changes and new features use termux-scripting.
---

# Code refactoring

Paths are relative to this skill directory. Load `termux-scripting` for dialect and style rules and `code-review` for the final review.

Research authority: search the web yourself when docs or dependency facts are missing or stale (primary sources first: Termux wiki, termux-packages, termux-app, Android and shell manuals); cite URLs; never guess.

## Contract
- Behavior is fixed: same stdout, stderr, exit codes, files written, environment variables set, and names defined (functions, aliases, variables, hooks, widgets, `source` order). A change to any of them is a feature or a fix; make it a separate task.
- One kind of change per step; each step is small enough to review and revert alone.
- No fixes, renames, or style edits outside the declared scope.
- Wrapper and CLI-integration code keeps its user-visible text, streams, and exit codes, and gets no prefixes. It can move; its messages do not change, including casing and punctuation.
- Do not assume file names. Find the code by searching definitions (`repo-map` definitions, `def-index`, `rg`/`grep`).

## Workflow
1. Scope: goal, the code to change, what stays identical (public names, CLI, output, load order), stop conditions. Fill `assets/refactor-plan.md`.
2. Baseline, before any edit. Keep baseline files in the workspace but outside tracked files under `.termux-agent/refactor/<topic>/` (or `.termux-agent/refactor/`).
   - `git --no-pager status --short`: unrelated edits are listed, not mixed in.
   - `lint-shell` (`termux-scripting`) on the files in scope: keep the SUMMARY line and findings.
   - `sh scripts/def-index.sh --out .termux-agent/refactor/before.tsv` (`.ps1` flavor available).
   - Behavior cases from `assets/cases.tpl` for each public command, function, and wrapper, then `sh scripts/behavior-snapshot.sh record --dir .termux-agent/refactor/snap --cases <cases> --source <module> ... [--stub-termux]`. List `--source` files in load order. Cases are deterministic. Device-only behavior stays UNVERIFIED with commands for the user.
3. Plan ordered steps. Each names one refactoring type (rename, extract function, inline, move, split file, merge files, remove duplication, replace construct) and its expected `def-index` effect (none, moved, renamed, added).
4. Apply one step. Then, before the next step:
   - `lint-shell` on touched files: no finding that the baseline did not have.
   - `sh scripts/def-index.sh --compare .termux-agent/refactor/before.tsv [--rename OLD=NEW]`: the result matches the step's expected effect. An unexpected `removed`, `added`, or `duplicate` stops the step.
   - `sh scripts/behavior-snapshot.sh compare --dir .termux-agent/refactor/snap --cases <cases> --source <module> ...`: every case is `same` unless the plan declared a difference.
   - After a rename or move, search the whole repository for the old name (code, docs, completions, install scripts).
   Fix or revert a failing step before continuing.
5. Moves and splits:
   - Move code verbatim in one step; edit it in later steps. In the `diff-collect` output the deleted and added blocks are identical apart from planned edits.
   - Each moved definition exists exactly once afterwards (`moved`, never `duplicate`).
   - Each new file is loaded by the project's existing mechanism, in a position that keeps the original definition order and source-time effects (aliases, `setopt`, hooks, `compdef`, traps). The `__state__` case lists functions, aliases, exports, and hooks present after sourcing; a missing `source` line shows there.
   - Name new files after the neighbors' convention; discover it, do not invent one.
   - When shell startup code moves, compare `time zsh -i -c exit` before and after (`termux-customization`).
6. Review with `code-review` (full diff coverage), then report with `assets/refactor-report.md` and the final report of `using-termux-skills`: one draft commit per step; no commits.

## Typical targets
Duplicated blocks to one function; long functions split by purpose; deep nesting to guard clauses; repeated tool checks to one helper; repeated literals to named variables; dead code (remove only after `def-index` plus a repository search show no use, and only when the user asked).

## Gotchas
- The index is line-based: dynamic definitions (`eval`, generated names, aliases built at runtime) are invisible to it. The `__state__` case covers them at runtime.
- Merging two similar functions changes behavior when they differ on edge cases: run both on those inputs first.
- Order at source time matters in zsh: an `alias`, `zstyle`, or `setopt` moved after its first use changes behavior.
- The sandbox runs on the host. Storage, Termux:API, and Android limits are not covered: list them as device checks.
- A baseline goes stale after an intentional behavior change: record a new one in a separate task.
- User-facing commands, aliases, and environment variables are interface: rename them only with the user's approval.
