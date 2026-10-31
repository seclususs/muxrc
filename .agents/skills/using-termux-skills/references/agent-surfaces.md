# Agent surfaces

What Google Antigravity loads from this setup. Source: vendor documentation; re-check the pages when behavior looks different.

## Antigravity (App, CLI, IDE)
| Item | Behavior | Source |
|---|---|---|
| `AGENTS.md` | Plain Markdown without frontmatter; always-on pointer to rules and skills. | antigravity.google/docs/rules |
| `.agents/rules/*.md` | Rules directory (the docs default to `.agents/` and keep `.agent/` as a legacy path). Each file needs frontmatter with `trigger` set to `always_on`, `model_decision`, `glob`, or `manual`; a file without it is dropped. An `always_on` rule is injected into the system prompt on every turn. Limits: 24 KB per file, 20,000 tokens for all always-on rules. | antigravity.google/docs/rules |
| `.agents/skills/<name>/SKILL.md` | Skills directory (same `.agents/` default, `.agent/` legacy). Name and description are listed at the start; the agent decides from the description whether to read the rest. A skill can also be invoked by name (`/<skill-name>`). The Customizations panel lists the skills that loaded. | antigravity.google/docs/skills |
| Subagents | App and CLI. Tool `invoke_subagent`; built-in types `research` (codebase research; its write access is not documented), `self` (a clone of the caller with the same instructions and tools), and `browser` (only through `/browser`); custom types through `define_subagent`. A subagent starts without the parent's conversation and inherits the parent's allowed command prefixes, file scopes, and sandbox settings. | antigravity.google/docs/subagents |
| Tool arguments | `invoke_subagent`: `Subagents`, an array whose items hold `Prompt`, `Role`, `TypeName`, `Workspace?`. `define_subagent`: `name`, `description`, `system_prompt`, `enable_mcp_tools?`, `enable_write_tools?`, `enable_subagent_tools?`. `send_message`: `Recipient`, `Message`. `manage_subagents`: `Action` (`list`, `kill`, `kill_all`), `ConversationIds`. | antigravity.google/docs/hooks |

## Context
Antigravity compacts older turns into checkpoint summaries as a conversation grows; `/context` shows them, and `/clear` starts clean between unrelated tasks (antigravity.google/docs/cli/commands/context). Exact values from earlier tool output (paths, flags, versions) are not reliable after compaction: re-run the tool or re-open the file.

## Consequences for this setup
- Antigravity loads `AGENTS.md` and `.agents/rules/core-policy.md` by itself and lists the skills in `.agents/skills/`.
- Subagent briefs travel as prompts through `invoke_subagent` directly; see `subagent-development`.
