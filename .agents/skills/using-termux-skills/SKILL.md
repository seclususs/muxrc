---
name: using-termux-skills
description: Entry skill, read on every user message. Separates discussion from tasks, loads project context, asks when a request is ambiguous, and routes tasks to the domain skills. Read it before any other action.
---

# Using Termux skills

Read this file at the start of every user message, also when an earlier turn already read it. Rules, script invocation, and the `.artifacts/` layout: core policy.

## Mode
Decide the mode from the message. Do not announce it and do not ask the user to pick.

| Mode | Messages | Do |
|---|---|---|
| Discussion | Question, explanation, opinion, comparison, brainstorm, status, "why" | Answer directly. Ground each project fact in a file opened now (file:line) and each platform fact in a primary source. No implementation or code changes. Open a skill's reference only when the answer needs its facts. |
| Task | Edits files, runs commands, reviews or analyzes diffs/changes, debugs, researches for a deliverable, produces code or config | Procedure below. |

A discussion that ends in a decision to change something, or any request inspecting diffs or what changed, is a task. When the mode itself is unclear, ask (core policy, Ambiguity gate).

## Task procedure
1. Project: follow core policy, Project understanding. `sh .agents/skills/using-termux-skills/scripts/repo-map.sh [--root DIR] [--max N]` (or the `.ps1` flavor) prints read-only repository facts: `git`, `conf` (config files and README), `dirs`, `dialect.*`, `shebang`, `def` (definitions as FILE:LINE), `termux_cmds`, `logui.*` (logger convention), and `commits` (subject style). It lists no documentation beyond the README: search for the rest. Read the config files it lists (`.editorconfig`, `.shellcheckrc`, `.gitattributes`) when style or line endings matter.
2. Ambiguity: resolve it by asking before any work.
3. Route: open the `SKILL.md` of each skill the routing table names, before the first edit or script run; do not ask the user whether to use a skill. Reopen it when its text is no longer in context; a summary of a skill is not the skill.
4. Host: before the first host command, and again after a "not found" failure, open `.agents/skills/platform-detection/SKILL.md` and follow it. `run.scripts` in its output picks `.sh` or `.ps1` for every other script.
5. Facts: a package, flag, API, version, or platform behavior that is missing or may be stale: search the web (primary sources first) and cite the URL.
6. Plan when the task is not trivial (`assets/task-plan.md`, saved as `.artifacts/scratch/plan.md`) and apply the delegation gate. High risk: stop and wait for the user's go.
7. Work, then the lint gate and `code-review`, then the report.

A subagent that received a brief skips this procedure and follows the brief (`subagent-development`).

## Routing
| Request | Open, in order |
|---|---|
| What changed; explain or analyze a diff, commit, or file | `code-review` (change analysis) |
| Review, audit, "find bugs", "is this correct", pre-commit check | `code-review` |
| Error, crash, wrong output, hang, "not working" | `systematic-debugging` (+ `termux-environment`) |
| Restructure without behavior change: rename, extract, move, split, merge, deduplicate, simplify | `code-refactoring` (+ `termux-scripting`) |
| Write or change a script, function, wrapper, installer, alias | `termux-scripting` (+ `termux-environment`) |
| Theme, properties, prompt, init, startup speed | `termux-customization` (+ `termux-scripting`) |
| Ideas, roadmap, "what should I add" | `feature-ideation` (stop at the user's choice), then implement |
| How Termux or Android behaves (paths, storage, packages, permissions, root), or a check that needs the device | `termux-environment` (device checks over SSH) |
| A host tool is missing or failing | `platform-detection` |
| Delegation gate met, or the user asks for subagents, parallel work, delegation, or a second opinion | `subagent-development` |

A request that matches several rows opens all of them. Process skills (`systematic-debugging`, `code-refactoring`, `feature-ideation`) come before implementation skills (`termux-scripting`, `termux-customization`). Every code change ends with `code-review` and the lint gate. A review that also asks for fixes reports first (`code-review`); edit only the findings that pass its finding gate.

## Task shortcuts that fail
| Thought | Action |
|---|---|
| I already know the answer | Verify it in the repository or a primary source first. |
| The diff looks fine | A diff shows what changed, not what it calls. Check that every command, flag, function, and path it uses exists (`code-review`). |
| The detector already ran | Its output is a snapshot. A path, flag, or version not visible in context is unknown: run it again. |
| I know where bash or zsh is | Call the tool by its `tool.NAME` path from the detector output. |
| I will run it to see what happens | Only through `sandbox-run` or `trace-run`, never directly on the host. |
| I checked it by hand | Verification is the lint gate and `code-review`; ad-hoc commands do not replace them. |
| I was asked to find bugs, so I must report some | A finding needs evidence and an intent check (`code-review`, finding gate). No findings is a valid result. |
| It looks wrong or inconsistent | Run the intent check (core policy): history and comments may record why. |
| The linter reports INFO | INFO is a lead, not a defect: do not edit only to silence it. |

## Delegation gate
Defined in core policy. Evaluate it after the plan exists, before the first edit, and record `Delegation gate: met | not met` in the plan. Met: open `subagent-development`. Not met: work directly.

## Scale to risk
Risk follows the impact of the change, not the file or its role.
- Trivial (one file, about 10 lines, no behavior change, in any code role): do it inline, run the lint gate, no plan, no subagents.
- Standard: research, plan, implement, review, test.
- High (destructive or irreversible actions, network or system-modifying installs, a behavior change to a wrapper or installer, many files, a repository-wide review with fixes): Standard, plus two review stages and the user checkpoint of the core policy.

## Long conversations
Older turns are compacted into summaries, so earlier values can be stale or lost. Keep the goal and open items in the plan file, not in memory. Before a major step and before the report, reopen the plan and the files in scope, and rerun any command whose output you are about to quote. A new unrelated task starts again at Mode with fresh project facts.

## Reporting
- Tasks that change files: `assets/final-report.md`.
- Review and change analysis: the report templates of `code-review`.
- Discussion: answer directly with evidence (file:line or source URL).

## Gotchas
- A missing tool is not a blocker: use the fallback and state the reduced coverage.
- Repository facts go stale: rerun `repo-map` when the tree changed during the task.
- Subagent output is a claim, not evidence: rerun checks yourself before reporting.
- What each agent surface loads from this setup (rules, skills, tools): `references/agent-surfaces.md`.
