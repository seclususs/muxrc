**ENVIRONMENT:** All files/code are exclusively developed for Termux.
If testing or executing outside of a native Linux, `git bash` MUST be used.

## 1. REQUIRED SKILLS

- MUST invoke **Superpowers plugin/skill**
  (e.g., `brainstorming`, `systematic-debugging`, `writing-plans`)
  before any action, coding, or answering.

## 2. STRICT WORKFLOW (NO AUTOPILOT)

- NEVER auto-commit. Execution MUST PAUSE before `git add`.
- Before pausing, output:
  1. Changed files summary.
  2. Draft commit message.
  3. Request for explicit manual approval.

## 3. SHELL (bash/zsh) STANDARDS

- **Safety:** `set -euo pipefail`.
- **Syntax:** `$()` (NO backticks), `"$VAR"`, `local` for function scope,
  explicit `exit 0`.
- **Naming:** Lowercase `local` vars, UPPERCASE global/env vars.
- **Style:** Modular, self-documenting code. NO redundant comments.

## 4. LOGGING UI

- STRICTLY flat (zero-indent) and completely lowercase.
- Prefixes:
  - `[*]` info
  - `[+]` success
  - `[-]` warn/skip
  - `[!]` error
- Example: `echo "[+] configuration loaded."`

## 5. COMMENTING

- Use exact-length hash borders for structural/block comments.
  NO inline `#` for blocks.

```text
#######
# title
#######
```

## 6. COMMIT FORMAT

- NO prefixes (e.g., DO NOT use `feat:`, `fix:`).
- **Subject:** Imperative mood (`Add`, `Update`, `Refactor`, `Drop`, `Fix`),
  max 52 chars, NO trailing period.
- **Body:** Leave one blank line after subject; wrap text at 72 chars.
