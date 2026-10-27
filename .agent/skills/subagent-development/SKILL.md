---
name: subagent-development
description: Runs multi-step or multi-file work as research, implementation, review, and test roles, using Antigravity subagents (invoke_subagent, define_subagent) or sequential passes in one session when no subagent tool exists. Covers briefs, workspace modes, least-privilege tool settings, handoff format, review loops, and the final report. Use for work that touches several files, needs parallel research or independent review, or carries high risk.
---

# Subagent development

Paths are relative to this skill directory. Briefs and the policy digest are in `assets/`.

Research authority: search the web yourself when docs or dependency facts are missing or stale (primary sources first: Termux wiki, termux-packages, termux-app, Android and shell manuals); cite URLs; never guess.

## Roles
research (read-only), implementer, reviewer (read-only), tester. Fill every placeholder of `assets/brief-*.md`; paste `assets/policy-digest.md` into each brief.

## Antigravity subagent tools
- `invoke_subagent`: parameters `TypeName`, `Role`, `Prompt`, `Workspace`. The prompt is the brief.
- Built-in types: `research` (read-only) fits the research and reviewer roles; `self` (full tools) fits the implementer and tester roles.
- `Workspace`: `inherit` for sequential edits; `branch` (isolated git worktree) for parallel edits that may overlap, then merge; `share` (shared directory) only when agents must see each other's files live.
- `define_subagent` registers a reusable named role: `name`, `description`, `system_prompt`, `enable_write_tools`, `enable_mcp_tools`, `enable_subagent_tools`. Least privilege: `enable_write_tools=false` for research and reviewer roles; `enable_subagent_tools` only for a role that must delegate. Named roles are optional.
- A subagent starts with a clean context and does not see this chat. The brief is self-contained: goal, scope, constraints, acceptance criteria, output format, policy digest. Pass the parent conversation ID only when the subagent must message back.
- A dispatched subagent skips the entry procedure of `using-termux-skills`; the brief names the skills it reads.
- Do not poll a running subagent in a loop; Antigravity wakes the parent when it reports.
- Parallelize only independent units with disjoint files; otherwise run sequentially.
- Separation: the implementer does not review its own work; research and review do not edit; the tester reports and does not fix.
- Hand off compact facts (file:line, commands, exit codes), not narrative.
- No subagent tool (standalone IDE), or a subagent hangs or returns nothing: run the same roles as separate sequential passes in this session. Before the review and test passes, re-run `diff-collect` and re-read the changed files from disk; ignore your memory of why they changed.

## Phases
1. Research: answer open questions with evidence (code or web). Output FACTS / UNKNOWNS / RISKS.
2. Plan: acceptance criteria, files in scope, test plan, rollback. Minimal; no speculative scope. High risk: pause for approval.
3. Implement: smallest correct change using the domain skill (`termux-scripting`, `termux-customization`, `systematic-debugging`, `code-refactoring`).
4. Review: stage A, spec compliance (missing or extra behavior); stage B, quality and safety through `code-review`, including `diff-collect` and its coverage line. Fix blockers and majors, then re-review. At most 3 rounds, then report the open findings.
5. Test: lint gate and sandbox (`termux-scripting`), `--twice` idempotency, a regression check for bug fixes, `behavior-snapshot compare` for refactors. Mark what needs a Termux device, with exact commands.
6. Report with `using-termux-skills` `assets/final-report.md`. Do not run `git add` or commit.

## Gotchas
- Subagent output is a claim, not evidence: re-run the lint gate yourself before reporting.
- A missing tool is not a blocker: use the fallback and state the reduced coverage.
- Briefs drift from policy when written from memory: paste the digest.
- Over-permissioned or unscoped subagents edit what they should only read: set tool access per role and list files in scope.
