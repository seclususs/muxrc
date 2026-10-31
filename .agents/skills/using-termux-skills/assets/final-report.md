# Final report

Delete any section that does not apply. One fact per line.

## Changes
- `path`: what changed and why, in at most 12 words

## Verification
- Host: `host.os`/`host.env` and `run.scripts` from platform-detection; reduced coverage, if any
- Lint gate: the `SUMMARY` line
- Review: the coverage line of `code-review`
- Other command run: result (test output, harness report)
- Not verified on host: item that needs a Termux device, with the exact command to run there

## Draft commit
```text
Imperative subject, at most 52 chars, no trailing period

- What changed and why; flat single-level bullets, wrapped at 72
```

## Approval
Stage and commit the files above with this message?
Open decisions: none | list them.

`git add` and `git commit` wait for the answer.

## Commit subject examples
- Good: `Add idempotent storage setup check`
- Bad: `feat: added storage check.` (prefix, past tense, trailing period)
