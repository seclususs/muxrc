# Plan: one-line task summary

Save as `.artifacts/temp/plan.md`; reopen it after each step and before the report. Keep what the task needs; a trivial task needs one line.

## Requirements
- R1: an explicit requirement from the request, one line each (ask or inspect for anything unclear)

## Project facts
- What the project does and where this change fits, with file:line
- Conventions in use: shell dialect, logger, naming, formatting
- Files in scope (found with repo-map or search, not from memory) and what stays untouched on purpose

## Checks
Written before the code. A check is not weakened or dropped later without a stated reason.
- Behavior, whole change: R1 -> the observable result and how it runs (a `sandbox-run` case, a device command)
- Boundary: R1 -> platform, Termux runtime, dialect, flags, paths, config keys, and the check that covers them (`code-review` against this plan, `check-termux-config`, `diff-collect`)
- Unit: R1 -> contract of each function or command (quoting, exit codes, errors, idempotency) and its check (lint, test harness, a sandbox case)

## Steps
1. Step. Done when: the command or observation that shows it worked.

## Risk
- trivial | standard | high, with the reason. High: stop and wait for the user's go before the first edit.
- Needs the Termux device: item and exact command, or none.
- Open questions: only those that block the work; ask them before the first edit.
