# Refactor plan

Goal: <one sentence>
Scope: <code to change, found by search; no assumed file names>
Contract (stays identical): <public names, CLI and output, exit codes, files written, environment variables, load order>
Baseline: <lint SUMMARY; def-index file; behavior-snapshot directory and case count>
Steps
1. <refactoring type>: <what> | expected def-index effect: <none | moved | renamed | added> | cases touched: <names>
2. <...>
Stop conditions: <unexpected removed, added, or duplicate; any behavior DIFF; any new lint finding>
Rollback: <revert step N, or restore the files in scope from git>
Device checks: <cases the sandbox cannot cover, with exact commands>
