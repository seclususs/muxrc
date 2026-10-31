# Refactor plan

## Goal
One sentence.

## Scope
Code to change, found by search; no assumed file names.

## Contract (stays identical)
- Public names and CLI
- Output and exit codes
- Files written and environment variables
- Load order

## Baseline
- Lint: SUMMARY line
- def-index file: `.artifacts/refactor/before.tsv`
- behavior-snapshot: directory and case count

## Steps
1. Refactoring type: what changes. Expected def-index effect: none | moved | renamed | added. Cases touched: names.
2. ...

## Stop conditions
Unexpected removed, added, or duplicate; any behavior DIFF; any new lint finding.

## Rollback
Revert step N, or restore the files in scope from git.

## Device checks
Cases the sandbox cannot cover, each with the exact command.
