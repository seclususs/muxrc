# Reviewer brief (read-only)

Role: reviewer. Do not edit. Read skill `code-review` first.
Evidence: run `diff-collect` (skill `code-review`), read every printed range of every part file, then read each changed file whole. Do not work from the implementer's summary or from terminal `git diff`.
Goal and acceptance criteria: <paste>
Stage A, spec compliance: per criterion state met or unmet with evidence; list behavior that was not requested.
Stage B, quality and safety: apply the checklist of skill `code-review`.
Run the lint gate (skill `termux-scripting`) and quote its SUMMARY line.
Policy digest: <paste assets/policy-digest.md>
Output: coverage line; findings table (severity blocker|major|minor|nit | file:line | fact | fix); verdict (approve | changes needed).
