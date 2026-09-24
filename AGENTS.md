# AGENTS

## 1. Plugin Requirement

All AI agents must utilize the **Superpowers plugin/skill** as the primary
framework for execution. Before taking any action, answering questions, or
writing code, invoke the appropriate skill
(e.g., `brainstorming`, `systematic-debugging`, `writing-plans`).

## 2. Development Workflow & The Absolute Rule

- **PAUSE AND AWAIT APPROVAL:** AI agents do not have the authority to
  automatically commit code. When files are ready to be staged (`git add`)
  or committed (`git commit`), execution must be **paused**.
- During this pause, output:
  - A concise summary of the files changed.
  - A draft commit message (following Section 6 rules).
  - A prompt requesting explicit manual approval.
- Do not proceed until explicit approval is granted.

## 3. Shell (`sh` & `zsh`) Coding Standards

Apply best practices intelligently based on context. Do not be overly rigid;
adapt standard conventions to fit the specific needs of the code.

- **Self-Documenting Code:** Use clear, descriptive variable names and
  modular functions. Avoid redundant comments.
- **Strict Mode:** Use `set -euo pipefail` where appropriate, but adapt
  to the script's needs
  (e.g., disable if a failing command is intentionally handled).
- **Modern Syntax:** Use `$()` for command substitution, not backticks.
  Wrap variables in double quotes (`"$VAR"`).
- **Scoping:** Use `local` for variables inside functions.
- **Clean Exits:** Terminate scripts cleanly
  (e.g., use `exit 0` for success when applicable).

## 4. UI and Logging Style

Keep all terminal output lowercase and concise.
Maintain a consistent UI logging format:

- `[*]` for general information or process start.
- `[+]` for success.
- `[-]` for warnings or skipped actions.
- `[!]` for errors or critical failures.

Use a 4-space indentation for sub-steps inside a broader task block:

```sh
echo "[*] initializing setup..."
echo "    [+] configuration loaded."
```

## 5. Commenting Style

Format structural or block explanations using this exact block style.
The top and bottom hash borders must exactly match the length of the
text string. Do not use inline `#` for block explanations.

```text
#######
# title
#######
```

## 6. Commit Message Rules

- **No Prefixes:** Do not use `feat:`, `fix:`, `chore:`, etc.
- **Imperative Mood:** Start the subject line with a capitalized
  imperative verb (`Add`, `Drop`, `Fix`, `Update`, `Refactor`).
- **Length:** Subject line maximum 52 characters, no trailing period.
- **Detailing:** Leave one blank line after the subject;
  wrap the body text at 72 characters.

**Correct:**
`Update termux vault encryption algorithm`
