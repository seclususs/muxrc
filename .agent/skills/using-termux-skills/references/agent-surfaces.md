# Agent surfaces

What Google Antigravity loads from this setup. Source: vendor documentation; re-check the pages when behavior looks different.

## Antigravity (App, CLI, IDE)
| Item | Behavior | Source |
|---|---|---|
| `AGENTS.md` | Plain Markdown without frontmatter; always-on pointer to rules and skills. | antigravity.google/docs/rules |
| `.agent/rules/*.md` | Rules directory. Each file needs frontmatter with `trigger` set to `always_on`, `model_decision`, `glob`, or `manual`. Limits: 24 KB per file, 20,000 tokens for all always-on rules. | antigravity.google/docs/rules |
| `.agent/skills/<name>/SKILL.md` | Skills directory. Name and description are listed at the start; the agent decides from the description whether to read the rest. A skill can also be invoked by name. | antigravity.google/docs/skills |
| Subagents | App and CLI. Tool `invoke_subagent`; built-in types `research` (read-only) and `self` (write tools); custom types through `define_subagent`. A subagent starts without the parent's conversation. | antigravity.google/docs/subagents |
| Tool arguments | `invoke_subagent`: `Prompt`, `Role`, `TypeName`, `Workspace?`. `define_subagent`: `name`, `description`, `system_prompt`, `enable_mcp_tools?`, `enable_write_tools?`, `enable_subagent_tools?`. `send_message`: `Recipient`, `Message`. `manage_subagents`: `Action` (`list`, `kill`, `kill_all`), `ConversationIds`. | antigravity.google/docs/hooks |

## Consequences for this setup
- Antigravity loads `AGENTS.md` and `.agent/rules/core-policy.md` by itself and lists the skills in `.agent/skills/`.
- Subagent briefs travel as prompts through `invoke_subagent` directly; see `subagent-development`.
