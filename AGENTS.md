# AGENTS

This document defines the required workflows, coding standards, and execution rules for AI agents operating in this repository. All automated code generation, modifications, and commits must comply with these instructions.

## 1. Development Workflow

Utilize the **Superpowers plugin** to structure the development and problem-solving process. The workflow must strictly adhere to the following sequence:

1. **Analyze:** Read and analyze all relevant context before writing any code. Completely read the relevant documentation for the specific feature or script being worked on.
2. **Write:** Execute the code following best practices, ensuring it is clean and modular.
3. **Review:** Self-review the code to ensure it meets the defined standards and solves the requested problem without introducing silent bugs.
4. **PAUSE (The Absolute Rule):** Stop execution. Proceed immediately to Section 2.

## 2. The Absolute Rule: PAUSE and Await Approval

AI agents do not have the authority to automatically commit code. When files are ready to be staged (`git add`) or committed (`git commit`), execution must be paused.

During this pause, output a response containing:

- A concise summary of the files changed and the logic updated.
- A draft of the commit message (following the rules in Section 5).
- A prompt requesting explicit manual approval.

Do not proceed until explicit approval is granted. The pause is intended for human review, code formatting, and logic verification. Execution of the commit is only permitted after this approval.

## 3. Shell (`sh` & `zsh`) Coding Standards

Apply modern, defensive programming principles to all shell scripts:

- **Self-Documenting Code:** Code must explain itself through clear, descriptive variable names and modular functions. Avoid redundant comments that explain obvious shell commands.
- **Strict Mode:** Enforce safety at the top of scripts to prevent silent pipeline errors:

  ```zsh
  set -euo pipefail
  ```

- **Modern Syntax:** Use `$()` for command substitution, not backticks. Wrap variables in double quotes (`"$VAR"`) to prevent word splitting.
- **Scoping:** Use `local` for all variables inside functions to avoid polluting the global namespace.

## 4. Commenting Style

When comments are required to explain the logic (why something is done) or to delineate sections, format them using this exact block style. The top and bottom hash borders must exactly match the length of the text string.

**Format:**

```text
#######
# Title
#######

#######################################
# This is a longer explanation sentence
#######################################

```

_Do not use standard inline `#` comments for structural or block explanations._

## 5. Commit Message Rules

All commit messages must strictly comply with the following constraints:

- **No Prefixes:** Do not use conventional commit prefixes (e.g., `feat:`, `fix:`, `chore:`).
- **Imperative Mood:** Start the subject line with a capitalized imperative verb (e.g., `Add`, `Drop`, `Fix`, `Update`, `Refactor`).
- **Length Constraint:** The subject line must be a maximum of 52 characters and must not end with a period.
- **Detailing:** If the commit requires more explanation, leave one blank line after the subject and wrap the body text at 72 characters.

**Correct Example:**
`Update Termux vault encryption algorithm`

**Incorrect Examples:**
`feat: update Termux vault encryption` (Fails: Uses prefix)
`Updated the script` (Fails: Past tense, not imperative)
`Refactor the toolkit deployment script to include better error handling` (Fails: Exceeds 52 characters)
