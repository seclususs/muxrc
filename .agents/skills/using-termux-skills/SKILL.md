---
name: using-termux-skills
description: Entry skill for every user message in this workspace, including questions, one-line requests, clarifications, and read-only analysis. Classifies the request and routes it to the domain skills - code-review (review and change analysis), systematic-debugging, code-refactoring, termux-scripting, termux-customization, termux-environment (including offline simulation), feature-ideation, platform-detection, subagent-development (delegation, parallel work, independent review). Read it at the start of a conversation, before any response or tool call.
---

# Using Termux skills

Paths are relative to this skill directory. Script invocation and the `.artifacts/` location: core policy.

## Procedure
1. Host: open `../platform-detection/SKILL.md` and follow it. It holds the detector command, how to read its output, and the fallbacks; `run.scripts` in the output picks `.sh` or `.ps1` for every other script. Do this before the first host command, and again after a "not found" failure.
2. Route: classify the message with the routing table and open the `SKILL.md` of every skill it names before the first edit or script run. Open it again when its text is no longer in context; a summary of a skill is not the skill.
3. If the request touches repository code or config: `sh scripts/repo-map.sh` (or `.ps1`). Read the config files it lists (`.editorconfig`, `.shellcheckrc`, `.gitattributes`) when style or line endings matter.
4. If a fact is missing or may be stale (package, flag, API, version, platform behavior): search the web, primary sources first, cite URLs, then continue.
5. Plan when the task is not trivial (`assets/task-plan.md`), apply the delegation gate, do the work, run the lint gate and `code-review`, report.

A subagent that received a brief skips this procedure and follows the brief (`subagent-development`).

## No exemptions
Questions, one-line requests, and read-only analysis follow the same procedure. Do not ask the user whether to use a skill. When no domain skill matches (a greeting, a general question), step 1 is the minimum.

| Thought | Action |
|---|---|
| It is only a question | Questions about code, diffs, shells, or Termux map to a skill below. |
| It is read-only | `code-review` covers read-only analysis of changes and files. |
| I already know the answer | Verify against the repository or a primary source, and load the skill. |
| I need more context first | Load the skill first; it defines how to gather context. |
| The change is trivial | Trivial changes still pass the lint gate and the review stage. |
| The detector already ran | Its output is a snapshot. A path, flag, or version not visible in context is unknown: run it again. |
| I know where bash or zsh is | Call the tool by its `tool.NAME` path from the detector output. |
| I will run the script to see what happens | Only through `sandbox-run` or `termux-sim`, never directly on the host. |
| I checked it by hand | Verification is the lint gate and `code-review`; ad-hoc commands do not replace them. |

## Routing
| Request | Open, in order |
|---|---|
| What changed; explain or analyze a diff, commit, or file | `code-review` (change analysis) |
| Review, audit, "is this correct", pre-commit check | `code-review` |
| Error, crash, wrong output, hang, "not working" | `systematic-debugging` (+ `termux-environment`) |
| Restructure without behavior change: rename, extract, move, split, merge, deduplicate, simplify | `code-refactoring` (+ `termux-scripting`) |
| Write or change a script, function, wrapper, installer, alias | `termux-scripting` (+ `termux-environment`) |
| Theme, properties, prompt, init, startup speed | `termux-customization` (+ `termux-scripting`) |
| Ideas, roadmap, "what should I add" | `feature-ideation` (stop at the user's choice), then implement |
| How Termux or Android behaves (paths, storage, packages, permissions, root), or a check that needs a device | `termux-environment` (simulate on the host with `termux-sim`) |
| A host tool is missing or failing | `platform-detection` |
| Delegation gate met (below), or the user asks for subagents, parallel work, delegation, or a second opinion | `subagent-development` |

A request that matches several rows opens all of them. Process skills (`systematic-debugging`, `code-refactoring`, `feature-ideation`) come before implementation skills (`termux-scripting`, `termux-customization`). Every code change ends with `code-review` and the lint gate.

## Delegation gate
Defined in core policy. Evaluate it after the plan exists, before the first edit, and record `Delegation gate: met | not met` in the plan. Met: open `subagent-development`. Not met: work directly.

## Scale to risk
- Trivial (one file, about 10 lines, no behavior change): do it inline, run the lint gate, no plan, no subagents.
- Standard: research, plan, implement, review, test.
- High (wrappers, installers, destructive or network actions, many files): Standard, plus two review stages and a user checkpoint after the plan.

## Reporting
- Tasks that change files: `assets/final-report.md`.
- Review and change analysis: the report templates of `code-review`.
- Questions: answer directly with evidence (file:line or source URL).

## Gotchas
- A missing tool is not a blocker: use the fallback and state the reduced coverage.
- Repository facts go stale: re-run `repo-map` when the tree changed during the task.
- Subagent output is a claim, not evidence: re-run checks yourself before reporting.
- Do not copy repository paths into notes meant to outlive the task.
- What each agent surface loads from this setup (rules, skills, subagents): `references/agent-surfaces.md`.
