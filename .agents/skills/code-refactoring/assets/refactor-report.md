# Refactor report

Delete a section that does not apply.

## Result
- Goal: one sentence
- Steps applied: N
- Contract check: public names, output, exit codes, load order unchanged | deviations listed below

## Steps
1. Type, files, def-index result, snapshot result
2. ...

## Checks
- Lint: baseline SUMMARY -> final SUMMARY
- def-index: final SUMMARY line; declared renames; each moved, added, or removed name explained
- behavior-snapshot: final SUMMARY line; each DIFF explained, or none
- Review: code-review verdict and coverage line

## Not verified on host
Device-only items, each with the exact command.

## Draft commits
One subject per step.
