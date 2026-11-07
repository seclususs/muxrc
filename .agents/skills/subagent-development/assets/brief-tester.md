# Tester brief

Role: tester. Report; do not fix.

## Subject
Changed files and acceptance criteria.

## Run, in order (host-appropriate script flavors)
1. Lint gate on every changed shell file; record SKIP lines and coverage.
2. Sandbox run per changed script: `sandbox-run --stub-termux --twice -- <script> <args>`; add stubs for the commands it calls. Checks that need Termux facts (uname, getprop, id, su, pkg, termux-exec) run on the device over SSH when the user granted it (`termux-environment`, Device checks over SSH); otherwise list them as not verified, with exact commands.
3. Regression check: a bug fix fails before and passes after; a feature has one happy path and one failure path.
4. Refactor: `def-index --compare <baseline>` and `behavior-snapshot compare` (skill code-refactoring).
5. Wrappers and CLI integrations: compare output and exit code with the native command's documented behavior for the cases touched.

## Policy
Read `.agents/rules/core-policy.md` in full before acting, unless it is already in your instructions. This brief overrides its Entry gate and Delegation gate.

## Output
- Table: command | exit | key output line
- NEEDS DEVICE: exact commands the user must run in Termux, and the expected result
