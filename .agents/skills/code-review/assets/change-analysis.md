# Change analysis

Lead with two or three sentences on what changed overall, then only the parts that apply.

- Scope and coverage: what was compared and the scope flags; diff parts and line counts read in full; files read in full; skipped files; `verify=ok|mismatch`; references checked and unverified.
- Per file, `path` (status, +add -del):
  - What: code facts (functions, options, or commands added, deleted, or altered).
  - Where: function or section, file:line.
  - Effect: behavior change, or "none observed".
  - Intent: from the request, a commit message, or a comment; "inferred" when not stated.
- Risks and open points: behavior, Termux compatibility, wrapper or integration contract; unverified items, each with the command that would verify it.
