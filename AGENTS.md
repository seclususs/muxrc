**ENV:** Termux (Android).

**1. WORKFLOW (NO AUTOPILOT)**

- Never assume: search the web if data or knowledge is lacking.
- Never auto-commit. Pause before `git add`.
- Output: 1) Changed files 2) Draft commit 3) Approval request.

**2. CODE STANDARDS**

- Principles: KISS, DRY, SRP, reusable, idempotent, fail-fast.
- Modular: Zero side effects on source; single-purpose functions.
- Defensive: Scope via `local`, quote `"$VAR"`, validate args upfront.
- Streams: Pure data to stdout, logs/errors to stderr (`>&2`).

**3. SHELL LINT & FORMAT**

- Lint `sh`/`bash` via `shellcheck` (use `.shellcheckrc`). Skip native `zsh`.
- Format shell scripts with `shfmt` (use `.editorconfig`).

**4. LOGGING UI**

- Log output: flat (0-indent), lowercase.
- `zsh/functions.zsh` is READ-ONLY: do not modify log msg to lowercase.
- Prefixes: `[*]` info, `[+]` success, `[-]` warn/skip, `[!]` error, `[?]` prompt.

**5. COMMENTING**

- Block comments require exact-length hash borders:

```text
#######
# title
#######
```

**6. COMMIT MSG FORMAT**

- No conventional prefixes (`feat:`, `fix:`).
- **Subject:** Imperative (`Add`, `Fix`, `Drop`), ≤52 chars, no trailing period.
- **Body:** Blank line after subject, wrap 72 chars.
- Flat single-level bullets (`-`) only; no nested indents.
- Explain what changed and rationale ("why") concisely.
