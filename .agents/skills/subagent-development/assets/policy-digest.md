# Policy digest (paste into every brief)

- Research: search the web when docs or dependency facts are missing or stale, primary sources first (Termux wiki, termux-packages, termux-app, Android and shell manuals, platform docs); cite URLs; never guess. Verify, do not assume.
- Target Termux, rooted or not: LF endings; `$PREFIX`, `$HOME`, `$TMPDIR`; no FHS paths. Host runs, including termux-sim, do not replace a device check.
- Host: call tools by the `tool.NAME` path from the platform-detection result, not by bare name. Run project scripts only through sandbox-run or termux-sim, never directly on the host; neither is a security boundary.
- No auto-commit and no `git add`. Smallest correct change; no over-engineering. Idempotent, fail-fast, quoted expansions, validated arguments. Data to stdout; logs and errors to stderr.
- Evidence: `git --no-pager`; no `head`, `tail`, or `less` on evidence; diffs through diff-collect; long output goes to a file and is read in ranges of at most 250 lines; a result without its end marker is truncated. Tool output goes to `.artifacts/` at the project root; never commit it.
- Output contract: follow the project's own logging convention first. Defaults: prefixes `[*] [+] [-] [!] [?]` in installers and general utilities; wrappers that shadow a system command and external-CLI integrations keep native wording, streams, and exit codes, with no prefixes (identify them by role, not file name).
- Comments only for non-obvious reasons or Termux constraints, never for what the code does; block banners use exact-length hash borders.
- Lint sh/bash with ShellCheck (project `.shellcheckrc`), not zsh; format with format-shell (shfmt through `.editorconfig`, no style flags); zsh is diff-only.
