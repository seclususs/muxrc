# Tester brief

Role: tester. Report; do not fix.
Subject: <changed files and acceptance criteria>
Run in order, using the host-appropriate script flavors:
1. Lint gate on every changed shell file; record SKIP lines and coverage.
2. Sandbox run per changed script: `sandbox-run --stub-termux --twice -- <script> <args>`; add stubs for the commands it calls.
3. Regression check: bug fix = fails before, passes after; feature = one happy path and one failure path.
4. Refactor: `def-index --compare <baseline>` and `behavior-snapshot compare` (skill `code-refactoring`).
5. Wrappers and CLI integrations: compare output and exit code with the native command's documented behavior for the cases touched.
Policy digest: <paste assets/policy-digest.md>
Output: table of command | exit | key output line; then NEEDS DEVICE: exact commands the user must run in Termux and the expected result.
