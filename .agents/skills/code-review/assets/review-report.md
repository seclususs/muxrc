# Review report

Verdict first, then only the parts that apply. One fact per line.

- Verdict: approve | changes needed (N blocker, N major) | no findings
- Scope and coverage: files or diff summary and scope flags; diff parts and line counts read in full; files read in full; skipped files; `verify=ok|mismatch`; references checked and unverified; lint `SUMMARY` and coverage. Say that the review was not independent when you wrote the change.
- Spec compliance (stage A): each requirement or check of the plan, met or unmet, with evidence; behavior that was not requested: none or a list.
- Findings, ordered blocker, major, minor, nit; one block each:
  - `1. blocker: short title (path:line)`
  - Fact: what the code does, as observed.
  - Evidence: reproducer command and result (shell and version), or the rule violated and its source.
  - Intent check: the commit or comment found for these lines, or none.
  - Fix: the concrete change.
- Unverified leads: `path:line`, the suspicion, and what would confirm it (no severity, no edit).
- Needs device (unverified): item, the exact command to run in Termux, and the expected result.
