---
trigger: always_on
description: Core invariants for Termux-targeted shell projects. Applies to every message.
---

# Core Policy

## Entry gate
Every user message, including questions, clarifications, and read-only requests, starts here.
1. Open `.agents/skills/using-termux-skills/SKILL.md` with the file viewer in a new conversation, and again whenever its text is no longer in context (long session, or a checkpoint summary stands in for it).
2. Classify the message with its routing table and open the `SKILL.md` of every skill it names before the first edit or script run. Naming or remembering a skill is not reading it.
3. Before the first host command, follow `platform-detection` (open its `SKILL.md`).

A subagent that received a brief follows the brief instead.

## Delegation gate
After planning and before editing, open `subagent-development` when any of these holds: three or more files will change; two or more independent research questions exist; the task is high risk; the user asks for parallel work, delegation, or an independent review. Otherwise work directly.

## Target and host
- Target: Termux on Android (aarch64 primary; also arm, i686, x86_64), rooted or not. Use `$PREFIX`, `$HOME`, `$TMPDIR`; do not rely on FHS paths (`/usr`, `/etc`, `/tmp`, `/bin`). Files use LF.
- Host (Linux, macOS, Windows) is only the development environment. Do not assume its OS or tools. Take them from the `platform-detection` output: call a host tool by its `tool.NAME` path, not by bare name, and run the detector again when a path, flag, or version is not visible in context. State reduced coverage.
- Do not run project scripts or snippets directly on the host. Run them with `sandbox-run` or `termux-sim`; `-n` syntax checks and lint are the exception. These harnesses redirect `HOME`, `PREFIX`, and `TMPDIR` and stub commands; they are not a security boundary, so read a script for destructive commands first. With no POSIX shell on the host, do not run it; list it as a device check.
- Host runs, including `termux-sim`, show syntax, logic, and documented behavior, not Termux itself; list what needs a device check.
- Skill scripts print options with `--help`. Skill paths are relative to the skill directory (`.agents/skills/<name>/` from the project root). Run `.sh` with `sh`; run `.ps1` with `powershell -NoProfile -ExecutionPolicy Bypass -File <path> <args>` (`pwsh -NoProfile -File <path> <args>` on PowerShell 7).

## Artifacts
Files written by skill tools go to `.artifacts/<tool>/` at the project root, next to `.agents/`. Tools create the directory and put a `.gitignore` containing `*` inside it, so the content stays out of git. Do not stage or commit `.artifacts/`, and do not treat it as project code.

## Workflow
- Do not assume: verify in the repository or on the web, primary sources first.
- A code change is done after the lint gate and `code-review` ran on it. The report quotes each `SUMMARY` and coverage line; "verified" without a command and its result is not evidence.
- Never commit automatically; pause before `git add`. Final output: 1) Changed files 2) Draft commit 3) Approval request.
- Smallest correct change; no speculative options, abstractions, or dependencies.
- Discover paths and names by searching the repository. Do not hard-code file names in rules, skills, or scripts.

## Evidence integrity
- Terminal output can be cut by pagers, buffers, or tool limits. Run git as `git --no-pager`, and never pipe evidence through `head`, `tail`, or `less`.
- Diffs: run `diff-collect` (skill `code-review`), not `git diff` in the terminal.
- Output that may exceed about 200 lines goes to a file first (the tools' `--out` option), then is read in ranges of at most 250 lines up to the last line; confirm the total line count.
- A result missing its expected end (an `END` line, a closing line, the last line number) is truncated: read it again in smaller ranges.
- Read whole files, not only the changed hunks, before judging a change. State the coverage in the report.

## Code standards
- KISS, DRY, SRP, reusable, idempotent, fail-fast. No side effects on source; single-purpose functions.
- Defensive: scope variables (`local` where supported), quote `"$VAR"`, validate arguments up front.
- Streams: data on stdout; logs and errors on stderr (`>&2`).
- Lint sh/bash with ShellCheck (project `.shellcheckrc`); skip zsh. Format with `format-shell` (shfmt through `.editorconfig`, no style flags because flags disable it); zsh is diff-only because shfmt can corrupt zsh syntax.
- Lean and fast: no needless forks in loops or at shell startup.

## Output contract by code role
Follow the project's own convention first: `repo-map` reports logger use (`logui.*`) and recent commit subjects, and call sites show the rest. The defaults below apply when the project has none.
- Installers and general utilities: log text is flat (no indent) and lowercase, with prefixes `[*]` info, `[+]` success, `[-]` warn/skip, `[!]` error, `[?]` prompt.
- Wrappers that shadow a system command (for example `sudo`, `ls`, `grep`) and integrations with an external CLI: no prefixes and no project logger. Keep native wording, streams, and exit codes; do not restyle existing messages.
- Identify this code by what it does (search definitions and call sites), not by file name or path. Files can be split, merged, or moved; the contract stays with the code.
- Changing wrapper or integration code is allowed when the task needs it. Show native-behavior evidence: output and exit code before and after.

## Comments
- Write a comment only when it adds what the code does not show: a non-obvious reason, a Termux or Android constraint, a workaround, a hazard. Do not describe what the code does.
- Section banners use hash borders equal to the title length:
```text
#######
# title
#######
```

## Commit message
Match the style of recent commits when the history has one. Defaults:
- No conventional prefixes (`feat:`, `fix:`).
- Subject: imperative (`Add`, `Fix`, `Drop`), at most 52 chars, no trailing period.
- Body: blank line after the subject, wrap at 72. Flat single-level `-` bullets. Explain what changed and why, briefly.
- Do not split bullets into separate `-m` flags (git inserts blank lines between them); pass the body via a file (`git commit -F <file>`) or a single multiline argument.

## Writing style
- Reply in the user's language. Rules, skills, templates, and code comments are English.
- Plain, technical, direct: facts, evidence (file:line, command output), decisions.
- No praise, emphasis words, filler, restated questions, or closing recaps. State unknowns as unknown.

## Research authority
- Search the web yourself for Termux package and API details, tool flags, agent-platform behavior, and dependency facts. Primary sources first (Termux wiki, termux-packages, termux-app, Android and shell manuals, Antigravity documentation). Cite URLs. Never guess.
