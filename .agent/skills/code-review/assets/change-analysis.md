# Change analysis

Delete a section that does not apply.

## Overview
- Scope: what was compared; scope flags used
- Coverage: diff parts and line counts read in full; files read in full; skipped files; verify=ok|mismatch
- Summary: two or three sentences on what changed overall

## Files
### `path` (status, +add -del)
- What: code facts (functions, options, or commands added, removed, or altered)
- Where: function or section, file:line
- Effect: behavior change, or "none observed"
- Intent: from the request, a commit subject, or a comment; "inferred" when not stated

## Risks and open points
- Behavior, Termux compatibility, wrapper or integration contract
- Unverified items, each with the command that would verify it
