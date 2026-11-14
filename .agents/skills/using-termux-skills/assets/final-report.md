# Report

Lead with the result. Fit the report to the task: a simple edit gets a few lines; a multi-step task gets the parts below that apply, as short lists with one fact per line. Leave out empty parts.

- Result: `path`: what changed and why, in at most 12 words.
- Verification: each check of the plan with its result. Host (`host.os`/`host.env`, `run.scripts`) and any reduced coverage; the lint `SUMMARY` line; the `code-review` coverage line; harness or `sandbox-run` results; the device (SSH) command, its result, and that the device was left clean. Write "dynamic verification not performed" with the reason when behavior was not run.
- Evidence: per fix, the failing reproducer (shell and version) or the rule and source it violates; the intent check result when existing behavior changed.
- Not verified: items that need a Termux device, with the exact command to run there.
- Deviations from the request or the plan, with the reason.
- Commit: a draft message in the core policy format, then "Stage and commit these files with this message?" `git add` and `git commit` wait for the answer.
