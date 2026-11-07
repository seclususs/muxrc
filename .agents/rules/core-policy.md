---
trigger: always_on
description: Core invariants for Termux-targeted shell projects. Applies to every message.
---

# Core Policy

## Entry gate
Every user message, including questions, starts here.
1. Open `.agents/skills/using-termux-skills/SKILL.md` with the file viewer before any other action, on every message, even if an earlier turn already read it. Memory or a summary of it does not count.
2. Follow it: it separates discussion from tasks, routes tasks to skills, and says what to open. Open each routed `SKILL.md` before the first edit or script run; naming a skill is not reading it.
3. Before the first host command, open and follow `platform-detection`.
A subagent that received a brief follows the brief instead.

## Project understanding
Before the first edit, command, or claim about code in a task, learn the project from its files:
- Run `repo-map` (skill `using-termux-skills`) once per conversation, and again when the tree changed outside your edits. Read the README it lists (`conf`), then search for other docs (`docs/`, `*.md`, `--help` text) on the area you will change and read them.
- Read in full every file you will change and every file that calls or sources it. Search for existing helpers, logger, and naming before writing new ones.
- Put what the project does and where the change fits in the plan, with file:line. If you cannot, keep reading.
A function, flag, file, or behavior not seen in a search, a run, or a primary source is a guess, and a guess is not a finding.

## Ambiguity gate
Ask before acting when a request has two or more readings that lead to different work, or lacks a value you cannot find in the repository or on the web (target file, shell dialect, device, scope). Ask one short question with concrete options (tool `ask_question` when present, otherwise plain text) and wait. Do not assume, and do not ask what a search can answer.

## Delegation gate
After planning and before editing, open `subagent-development` when any of these holds: three or more files will change with separate logic (one mechanical edit repeated across files, such as a rename, counts as one unit); two or more independent research questions exist; the task is high risk; the user asks for parallel work, delegation, or an independent review. Otherwise work directly.

## Target and host
- Target: Termux on Android (aarch64 primary; also arm, i686, x86_64), rooted or not. Use `$PREFIX`, `$HOME`, `$TMPDIR`, not FHS paths (`/usr`, `/etc`, `/tmp`, `/bin`). Files use LF.
- Host (Linux, macOS, Windows) is only the development environment. Take its OS and tools from the `platform-detection` output: call a tool by its `tool.NAME` path, and run the detector again when a path, flag, or version is not visible in context. State reduced coverage.
- Run project scripts and snippets only through `sandbox-run` or `trace-run` (syntax checks with `-n` and lint are the exception). A snippet is a file under `.artifacts/scratch/`, run as `-- FILE`. Both harnesses redirect `HOME`, `PREFIX`, and `TMPDIR`; neither is a security boundary, so read a script for destructive commands first. With no POSIX shell on the host, do not run it.
- A host run shows syntax and logic, not Termux. When a check needs the device, ask once: "Can I reach your Termux device over SSH?" If the user answers with a command (for example `ssh termux`), follow `termux-environment`, Device checks over SSH; otherwise list the check with its exact command for the user.
- Skill scripts print options with `--help`. Run them from the project root by full path, `.agents/skills/<name>/scripts/<file>`; `assets/` and `references/` names in a `SKILL.md` are relative to that skill. Run `.sh` with `sh`; run `.ps1` with `powershell -NoProfile -ExecutionPolicy Bypass -File <path> <args>` (`pwsh -NoProfile -File` on PowerShell 7).

## Artifacts
Every file an agent tool or the agent creates for testing or scratch work lives under `.artifacts/<subfolder>/` at the project root, next to `.agents/`. Skill tools write to their own subfolder (`.artifacts/sandbox/`, `.artifacts/trace/`, and so on); manual files, test scripts, and temporary notes go to `.artifacts/scratch/`. Before the first manual write, make sure `.artifacts/.gitignore` exists and holds the single line `*`; tools create it, and you create it when it is missing. Do not stage or commit `.artifacts/`, and do not treat it as project code.

## Workflow
- Do not assume: verify in the repository or on the web, primary sources first.
- Evidence before change: a defect claim or a fix needs a failing reproducer run through a harness, or a documented rule it violates (cite the source). A non-behavioral defect (dead code, an unused variable) can instead rest on a deterministic check: a repository-wide search with no references, or a ShellCheck code such as SC2034 or SC2317. Lint INFO, style notes, and "could fail" are leads, not defects. "No findings" is a valid result.
- Intent check before changing or reporting code that looks wrong: `git --no-pager log -S'TEXT' --format='%h %s%n%b' -- PATH` (commits that added or removed TEXT; the reason is usually in the body) or `git --no-pager log -L START,END:PATH -s --format='%h %s%n%b'` (history of a line range), then read the nearby comments. No output means no matching commit. A recorded decision stands unless new evidence contradicts its reason.
- A code change is done after the lint gate and `code-review` ran on it. The report quotes each `SUMMARY` and coverage line; "verified" without a command and its result is not evidence.
- High risk (defined in `using-termux-skills`): stop after the plan and wait for the user's go before the first edit.
- Never commit automatically; pause before `git add`. Final output: Changed files, Draft commit, Approval request.
- Smallest correct change; no speculative options, abstractions, or dependencies.
- Discover paths and names by searching the repository. Do not hard-code file names in rules, skills, or scripts.

## Evidence integrity
- Terminal output can be cut by pagers, buffers, or tool limits. Run git as `git --no-pager`, and never pipe evidence through `head`, `tail`, or `less`.
- Diffs: run `diff-collect` (skill `code-review`), not `git diff` in the terminal.
- Output that may exceed about 200 lines goes to a file first (the tools' `--out` option), then is read in ranges of at most 250 lines up to the last line; confirm the total line count.
- A result missing its expected end (an `END` line, a closing line, the last line number) is truncated: read it again in smaller ranges.
- Read whole files, not only the changed hunks, before judging a change. State the coverage in the report.
- Older turns are compacted into summaries in long conversations. Treat remembered paths, flags, versions, and file contents as stale: reopen the file or rerun the command before relying on them.

## Code standards
- KISS, DRY, SRP, reusable, idempotent, fail-fast. No side effects on source; single-purpose functions.
- Defensive: scope variables (`local` where supported), quote `"${VAR}"`, validate arguments up front.
- Streams: data on stdout; logs and errors on stderr (`>&2`).
- Lint sh/bash with ShellCheck (project `.shellcheckrc`); skip zsh. Format with `format-shell` (shfmt through `.editorconfig`, no style flags because flags disable it); zsh is diff-only because shfmt can corrupt zsh syntax.
- Lean and fast: no needless forks in loops or at shell startup.

## Output contract by code role
Follow the project's own convention first: `repo-map` reports logger use (`logui.*`) and recent commit subjects, and call sites show the rest. The defaults below apply when the project has none.
- Installers and general utilities: log text is flat (no indent) and lowercase, with prefixes `[*]` info, `[+]` success, `[-]` warn/skip, `[!]` error, `[?]` prompt.
- Wrappers that shadow a system command (for example `sudo`, `ls`, `grep`) and integrations with an external CLI: no prefixes and no project logger. Keep native wording, streams, and exit codes; do not restyle existing messages.
- Identify this code by what it does (search definitions and call sites), not by file name or path. Files can be split, merged, or moved; the contract stays with the code.
- Changing wrapper or integration code is allowed when the task needs it. Show native-behavior evidence: output and exit code before and after.

## Log text
A Termux phone screen is narrow: about 50 columns at the default font and about 37 when zoomed.
- A log message is at most 36 characters, so a 4-character prefix plus the text fits 40 columns. Shorter is better.
- State the fact, not the story: no cause chains, no narration of steps, no repeated success messages. Log what the reader needs to act on.
- A message that needs more is split into several log calls of one short fact each, never one long line. A value such as a path goes on its own line.
```sh
# wrong: one long message
log_error "agent failed to run the task because the project context was not loaded"
# right: two short facts
log_error "project context not loaded"
log_error "agent task run aborted"
```

## Comments
- Write a comment only when it adds what the code does not show: a non-obvious reason, a Termux or Android constraint, a workaround, a hazard. Do not describe what the code does.
- No numbered or step comments (`# 1.`, `# Step 2`, `# First,`): they read like a tutorial. Name what a block is for, or write nothing.
- Section banners use hash borders equal to the title length:
```text
#######
# title
#######
```

## Commit message
Match the style of recent commits when the history has one. Defaults:
- No conventional prefixes (`feat:`, `fix:`).
- Subject: imperative (`Add`, `Fix`, `Drop`), at most 52 characters, no trailing period.
- Body: a blank line after the subject, then short paragraphs separated by blank lines. No bullets or lists. Each line at most 72 characters. Say what changed and why, one idea per paragraph.
- Pass the message with `git commit -F <file>`, or with one `-m` per paragraph (git puts a blank line between `-m` values, which fits paragraphs).
- Write the message file with the file-edit tool (Windows PowerShell redirection adds a BOM or UTF-16) and measure its line lengths with a command such as `awk '{ print length($0) }' FILE`, not by eye.

## Writing style
- Reply in the user's language. Rules, skills, templates, and code comments are English.
- Plain, technical, direct: facts, evidence (file:line, command output), decisions.
- No praise, emphasis words, filler, restated questions, or closing recaps. State unknowns as unknown.

## Research authority
- Search the web yourself for Termux package and API details, tool flags, agent-platform behavior, and dependency facts. Primary sources first (Termux wiki, termux-packages, termux-app, Android and shell manuals, Antigravity documentation). Cite URLs. Never guess.
