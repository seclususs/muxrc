# Reviewer brief (read-only)

Role: reviewer. Do not edit. Read skill code-review first.

## Evidence
Run diff-collect (skill code-review), read every printed range of every part file, then read each changed file whole. Do not work from the implementer's summary or from a terminal `git diff`.

## Goal and acceptance criteria
Paste them here.

## Stages
- Stage A, spec compliance: per criterion, met or unmet with evidence; map every hunk to a criterion, and list an unmapped hunk as behavior that was not requested.
- Stage B, quality and safety: apply the checklist of skill code-review.
- Run the lint gate (skill termux-scripting) and quote its SUMMARY line.

## Policy
Paste assets/policy-digest.md here.

## Output
Use the format of code-review/assets/review-report.md: coverage line, findings (severity, file:line, fact, evidence, intent check, fix), unverified leads, verdict (approve | changes needed | no findings).
