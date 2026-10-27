# Final report format

Use this order. Keep it short.

1) Changed files
- <path>: <what and why, at most 12 words>
Verification: <commands run and results; lint SUMMARY line; diff coverage when a review ran>
Not verified on host: <items needing a Termux device, with exact commands>

2) Draft commit
<subject: imperative, at most 52 chars, no trailing period>

- <what changed and why>
- <flat single-level bullets; wrap at 72>

3) Approval request
Stage and commit the files above with this message? <open decisions, if any>

Do not run `git add` or `git commit` before approval.

Commit examples
- Good: `Add idempotent storage setup check`
- Bad: `feat: added storage check.` (prefix, past tense, trailing period)
