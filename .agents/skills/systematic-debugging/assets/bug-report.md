# Bug report

Only the parts that apply, one fact per line.

- Symptom: exact error text and exit status.
- Environment: host or Termux (rooted or not); shell, dialect, and shell version.
- Reproducer: the command or minimal script, and where it ran (host harness, device over SSH).
- Evidence: trace excerpt with file:line and relevant outputs; the intent check of the lines to change (history, comments); full logs in `.artifacts/trace/<time>/`.
- Root cause: one sentence.
- Fix: what changed, and why it is the smallest change at the root cause.
- Verification: reproducer result before and after; lint `SUMMARY`; idempotency (second run); one neighboring case.
- Not verified on host: device-only items, each with the exact command and the expected result.
