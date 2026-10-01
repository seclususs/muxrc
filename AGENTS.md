**ENV:** Termux exclusive (use `git bash` if outside native Linux).

**1. WORKFLOW (NO AUTOPILOT)**

- NEVER auto-commit. PAUSE before `git add`.
- Must output: 1) Changed files summary 2) Draft commit msg 3) Request manual approval.

**2. SHELL STANDARDS**

- **Rules:** `set -euo pipefail`, `$()` only (no backticks), `"$VAR"`, explicit `exit 0`.
- **Naming:** `local` variables (lowercase), GLOBAL/ENV variables (UPPERCASE).
- **Style:** Self-documenting code, single-purpose functions. No redundant comments
  (explain "why", not "what").

**3. LOGGING UI**

- Strictly flat (0-indent) and lowercase. `zsh/functions.zsh` is READ-ONLY.
- Prefixes: `[*]` info, `[+]` success, `[-]` warn/skip, `[!]` error, `[?]` prompt.

**4. COMMENTING**

- Block comments MUST use exact-length hash borders. No inline `#` for blocks.

```text
#######
# title
#######
```

**5. COMMIT MSG FORMAT**

- NO conventional prefixes (e.g., `feat:`, `fix:`).
- **Subject:** Imperative mood (`Add`, `Fix`, `Drop`), ≤52 chars, no trailing period.
- **Body:** 1 blank line after subject, wrap at 72 chars.
