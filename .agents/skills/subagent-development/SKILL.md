---
name: subagent-development
description: Splits work into research, implementation, review, and test roles and runs them as separate subagents or as separate sequential passes. Use when the delegation gate is met (three or more files change, two or more independent research questions, high risk) or when the user asks to delegate, run in parallel, use subagents or agents, get an independent or second review, or verify with a fresh context. Covers briefs, workspace modes, least-privilege tool settings for Antigravity (invoke_subagent), handoff format, and the fallback when no subagent tool exists.
---

# Subagent development

Paths are relative to this skill directory. Briefs and the policy digest are in `assets/`.

## When to delegate
The gate is defined in core policy (three or more files, two or more independent research questions, High risk, or a user request). When the gate is not met, work directly and still end with `code-review`.

Delegation pays off for independent units: research questions that do not depend on each other, edits to disjoint files, a review by an agent that did not write the change. It does not pay off when each unit needs the previous unit's result; run those in order.

## Pick the mechanism
Check which tools the current session has. Do not assume.

| Situation | Mechanism |
|---|---|
| Tool `invoke_subagent` exists (Antigravity App or CLI) | Subagents, section below |
| No subagent tool (Antigravity IDE, feature off, or a call fails or hangs) | Sequential passes in this session, section below |

Per-surface facts and sources: `using-termux-skills/references/agent-surfaces.md`.

## Roles and briefs
research (read-only), implementer, reviewer (read-only), tester. Fill every placeholder of the matching `assets/brief-*.md` and paste `assets/policy-digest.md` into it. A brief is self-contained: goal, scope, constraints, acceptance criteria, output format. A subagent starts without this conversation and skips the entry procedure of `using-termux-skills`; the brief names the skills it reads.

Separation: the implementer does not review its own work; research and review do not edit; the tester reports and does not fix.

## Antigravity subagents
- `invoke_subagent` takes `Subagents`, an array; each item holds `Prompt` (the brief), `Role`, `TypeName`, and optional `Workspace`. One call can start several independent subagents.
- Built-in types: `research` (codebase research; the docs do not state its write access, so the brief also says "do not edit") fits the research and reviewer roles; `self` (a clone of the caller, same instructions and tools) fits the implementer and tester roles.
- `Workspace`: `inherit` for sequential edits; `branch` (isolated git worktree) for parallel edits that may overlap, merged afterwards; `share` only when agents must see each other's files live.
- `define_subagent` registers a reusable role: `name`, `description`, `system_prompt`, `enable_write_tools`, `enable_mcp_tools`, `enable_subagent_tools`. Least privilege: no write tools for research and reviewer roles; subagent tools only for a role that must delegate.
- `send_message` (`Recipient`, `Message`) reaches a running subagent; `manage_subagents` (`Action`: `list`, `kill`, `kill_all`) inspects or stops them.
- Subagents run asynchronously. Do not poll in a loop; the parent is woken when one reports.

## Sequential passes (no subagent tool)
Run the roles as separate passes in this session, in the order of the phases. Before the review and test passes, re-run `diff-collect` and re-read the changed files from disk; ignore your memory of why they changed. State in the report that the review was not independent.

## Phases
1. Research: answer open questions with evidence (code or web). Output FACTS / UNKNOWNS / RISKS.
2. Plan: `using-termux-skills/assets/task-plan.md`. High risk: pause for approval.
3. Implement: smallest correct change using the domain skill (`termux-scripting`, `termux-customization`, `systematic-debugging`, `code-refactoring`).
4. Review: stage A, spec compliance (missing or extra behavior); stage B, quality and safety through `code-review`, including `diff-collect` and its coverage line. Fix blockers and majors, then re-review. At most 3 rounds, then report the open findings.
5. Test: lint gate and sandbox (`termux-scripting`), `--twice` idempotency, `termux-sim` for environment-dependent scripts, a regression check for bug fixes, `behavior-snapshot compare` for refactors. Mark what needs a Termux device, with exact commands.
6. Report with `using-termux-skills/assets/final-report.md`. Do not run `git add` or commit.

Parallelize only independent units with disjoint files; otherwise run sequentially. Hand off compact facts (file:line, commands, exit codes), not narrative.

## Gotchas
- Subagent output is a claim, not evidence: re-run the lint gate and `diff-collect` yourself before reporting. Tool restrictions are settings, not proof; the diff shows what actually changed.
- A missing tool is not a blocker: use the fallback and state the reduced coverage.
- Briefs drift from policy when written from memory: paste the digest.
- An unscoped subagent edits what it should only read: set tool access per role and list the files in scope.
