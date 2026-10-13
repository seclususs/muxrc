**ENV:** Termux (Android).

**1. WORKFLOW (NO AUTOPILOT)**

- Never assume: search the web if lacking data or knowledge.
- Never auto-commit. Pause before `git add`.
- Output: 1) Changed files 2) Draft commit 3) Approval request.

**2. SHELL LINT & FORMAT**

- Lint `sh`/`bash` via `shellcheck` (use `.shellcheckrc`). Skip native `zsh`.
- Format shell scripts with `shfmt`.

**3. LOGGING UI**

- Log output: flat (0-indent), lowercase.
- `zsh/functions.zsh` is READ-ONLY: do not modify log msg to lowercase.
- Prefixes: `[*]` info, `[+]` success, `[-]` warn/skip, `[!]` error, `[?]` prompt.

**4. COMMENTING**

- Block comments require exact-length hash borders:

```text
#######
# title
#######
```

**5. COMMIT MSG FORMAT**

- No conventional prefixes (`feat:`, `fix:`).
- **Subject:** Imperative (`Add`, `Fix`, `Drop`), ≤52 chars, no trailing period.
- **Body:** Blank line after subject, wrap 72 chars.
- Flat single-level bullets (`-`) only; no nested indents.
- Explain what changed and rationale ("why") concisely.
