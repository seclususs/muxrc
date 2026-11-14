---
name: using-termux-skills
description: Entry skill, read on every turn. Use when starting to separate discussion from tasks, plan checks, route to domain skills, and verify completion.
---

# Using Termux skills

Rules, script invocation, and the `.artifacts/` layout: core policy.

## Mode
Decide the mode from the message. Do not announce it and do not ask the user to pick.
- Discussion (question, explanation, opinion, comparison, brainstorm, status, "why"): answer directly. Ground each project fact in a file opened now (file:line) and each platform fact in a primary source. No implementation or code changes. Open a skill's reference only when the answer needs its facts.
- Task (edits files, runs commands, reviews or analyzes diffs or changes, debugs, researches for a deliverable, produces code or config): the flow below.

A discussion that ends in a decision to change something, or any request inspecting diffs or what changed, is a task. When the mode itself is unclear, ask (core policy, Ambiguity gate). Each new unrelated task starts here again with fresh project facts.

## Task flow
A trivial task runs only the steps it needs (see Scale to risk).
1. Project: follow core policy, Project understanding. `sh .agents/skills/using-termux-skills/scripts/repo-map.sh [--root DIR] [--max N]` (or the `.ps1` flavor) prints read-only repository facts: `git`, `conf` (config files and README), `dirs`, `dialect.*`, `shebang`, `def` (FILE:LINE), `termux_cmds`, `logui.*` (logger convention), and `commits` (subject style). It lists no documentation beyond the README: search for the rest. Read the config files it lists when style or line endings matter.
2. Ambiguity: resolve it by asking before any work.
3. Route: open the `SKILL.md` of each skill in Routing before the first edit or script run; do not ask the user whether to use a skill. Reopen one when its text is not in context; a summary of a skill is not the skill.
4. Host: before the first host command, and again after a "not found" failure, open `.agents/skills/platform-detection/SKILL.md` and follow it. `run.scripts` in its output picks `.sh` or `.ps1` for every other script.
5. Facts: a package, flag, API, version, or platform behavior that is missing or may be stale: search the web and cite the URL (core policy, Evidence and research).
6. Plan before any code, script, or configuration is written (`assets/task-plan.md`; a trivial task needs one line). List the explicit requirements and write, for each, the checks that will show it is met: behavior (what the whole change does, observably), boundary (platform, Termux runtime, dialect, flags, paths, config keys), and unit (each function or command). Every check names the requirement it verifies and the expected result. Keep the plan in `.artifacts/temp/plan.md` or in the reply: a plan held only in memory bends to fit finished code. Reopen it before a major step and before the report. A written check is not weakened or dropped to get a pass; changing one needs a stated reason. Do not widen the scope, skip a requested step, or swap approaches silently; report each deviation with its reason.
7. Build: `code-writing` for shell code and behavior-preserving cleanup, `termux-customization` for Termux configuration. Write the test harness the plan names together with the code.
8. Verify the smallest unit first, each level against its own plan checks: unit (`format-shell`, `lint-shell`, test harness: `code-writing`); boundary (`check-termux-config` for `.properties` files: `termux-customization`; `diff-collect` and the review against the plan: `code-review`); behavior (the plan's behavior checks run with `sandbox-run`: `code-writing`).
9. A failed check goes to `systematic-debugging` for the root cause. The fix goes back through `code-writing` or `termux-customization`, then the affected level and every level above it run again. A cleanup is accepted only when the same checks pass before and after it.
10. Done, then report (below).

This skill starts on every message and, for a task, is finished when the mode is set, project facts are loaded, requirements and checks are written, and the routed skills are open. It hands off to `platform-detection` and the routed skills, and takes the work back for the closing check; a failed level returns to its owner (`code-writing`, `termux-customization`, or `systematic-debugging`).

## Routing
- What changed; explain or analyze a diff, commit, or file: `code-review` (change analysis).
- Review, audit, "find bugs", "is this correct", pre-commit check: `code-review`.
- Error, crash, wrong output, hang, "not working": `systematic-debugging` (+ `termux-environment`).
- Write or change a script, function, wrapper, installer, alias; or restructure without behavior change (rename, extract, move, split, merge, deduplicate, simplify): `code-writing` (+ `termux-environment`).
- Theme, properties, prompt, init, startup speed: `termux-customization` (+ `code-writing`).
- How Termux or Android behaves (paths, storage, packages, permissions, root), or a check that needs the device: `termux-environment` (device checks over SSH).
- A host tool is missing or failing: `platform-detection`.

A request that matches several rows opens all of them; `systematic-debugging` comes before the implementation skills (`code-writing`, `termux-customization`). A review that also asks for fixes reports first (`code-review`) and edits only the findings that pass its finding gate. A request for ideas or a roadmap is a discussion; implementing the chosen idea is a task.

## Done when
- The unit and boundary checks of the plan pass: the lint gate shows no ERROR, `code-review` leaves no open finding, and `check-termux-config` shows no ERROR when `.properties` files changed.
- The plan's behavior checks pass in `sandbox-run`, or on the device, when the change affects runtime behavior and the environment can run it. Otherwise the report says "dynamic verification not performed" and why.
- Ad-hoc commands do not replace these checks. The report quotes each `SUMMARY` and coverage line; "verified" without a command and its result is not evidence.
- Before reporting, compare the result with the requirement checklist, the planned checks, and this list. Report every deviation and every item that stayed unverified.

## Scale to risk
Risk follows the impact of the change, not the file or its role.
- Trivial (one file, about 10 lines, no behavior change, in any code role; a comment or documentation edit): do it inline and run the lint gate when code changed. The plan is one line.
- Standard: research, plan, implement, verify, review.
- High (destructive or irreversible actions, network or system-modifying installs, a behavior change to a wrapper or installer, many files, a repository-wide review with fixes): Standard, plus both `code-review` stages (spec, then quality) on the full diff, and the user checkpoint: stop after the plan and wait for the user's go before the first edit.

## Reporting
- Tasks that change files: `assets/final-report.md`.
- Review and change analysis: the report templates of `code-review`.
- Discussion: answer directly with evidence (file:line or source URL).
