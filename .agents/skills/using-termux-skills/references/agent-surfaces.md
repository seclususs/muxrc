# Agent surfaces

What Google Antigravity loads from this setup. Checked against the vendor pages on 2026-11-04; re-check them when behavior looks different.

## Antigravity (App, CLI, IDE)
| Item | Behavior | Source |
|---|---|---|
| `AGENTS.md` | Plain Markdown without frontmatter, always on. | antigravity.google/docs/rules |
| `.agents/rules/*.md` | Scanned flat (subfolders are ignored unless registered in `.agents/rules.json`); the docs default to `.agents/` and keep `.agent/` as a legacy path. Each file needs frontmatter with `trigger` (`always_on`, `model_decision`, `glob`, or `manual`); a file without a valid one is dropped silently. `always_on` rules are injected into the system prompt on every turn; `model_decision` rules add only path and description. Limits: 24,000 bytes per file and 20,000 tokens for all always-on rules; beyond that the largest files shrink to pointers. | antigravity.google/docs/rules |
| `.agents/skills/<name>/SKILL.md` | The agent sees the name and description of every skill on every turn and reads the full file only when the description looks relevant, so the description is the trigger. `description` is required; `name` is optional (default: the folder). Skills load from each parent folder up to the repository root. A skill can also be invoked by name (`/<skill-name>`). | antigravity.google/docs/skills |
| Tools the policy relies on | `view_file` opens files (flag `IsSkillFile`); `ask_question` asks the user multiple-choice questions (`questions` holding `question`, `options`, `is_multi_select`). | antigravity.google/docs/hooks |
| Hooks | The `PreInvocation` event can inject a message before each model call. This setup adds no hooks. | antigravity.google/docs/hooks |
| Subagents | App and CLI only; tool `invoke_subagent`. Types, workspace modes, and parameters: `subagent-development`. Custom types are transient (`define_subagent`) or Markdown files in `.agents/agents/<name>.md` (frontmatter `name`, `description`, `tools`, `subagent`, `model`; `subagent: true` allows `invoke_subagent`; a misspelled tool in `tools` can hang the subagent). A subagent starts without the parent's conversation and inherits the parent's allowed command prefixes, file scopes, and sandbox settings. | antigravity.google/docs/subagents |

## Context
Antigravity compacts older turns into checkpoint summaries as a conversation grows; `/context` shows them, and `/clear` starts clean between unrelated tasks (antigravity.google/docs/cli/commands/context). Exact values from earlier tool output (paths, flags, versions) are not reliable after compaction: reopen the file or rerun the tool.

## Consequences for this setup
- `AGENTS.md` and `.agents/rules/core-policy.md` are both always on, so the entry gate reaches the model on every turn. The descriptions of the skills are the only other skill text present every turn; the entry skill itself is read through the gate.
- Subagent briefs travel as prompts through `invoke_subagent`; see `subagent-development`.
