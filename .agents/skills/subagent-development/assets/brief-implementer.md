# Implementer brief

Role: implementer. Edit only the files in scope. Do not stage or commit.

## Goal
The behavior to deliver, in one paragraph.

## Acceptance criteria
1. Numbered, testable.

## Scope
- Files in scope: discovered paths
- Out of scope: everything else, including wrapper and CLI-integration code unless the goal changes it

## Inputs
- Facts: research output, relevant repo-map lines, platform-detection result
- Skills to follow: termux-scripting | termux-customization | systematic-debugging | code-refactoring

## Policy
Paste assets/policy-digest.md here.

## Definition of done
- The lint gate reports no ERROR.
- A second run changes nothing (idempotent).
- No behavior change outside the goal; no new dependency unless the goal requires it.

## Output
- Changed files: path, one-line reason
- Commands run, with exit codes
- Residual risks
