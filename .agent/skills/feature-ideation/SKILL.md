---
name: feature-ideation
description: Proposes new, evidence-based features for a Termux shell environment by mapping existing capabilities, finding gaps, and checking Termux feasibility. Use for ideas, a roadmap, "what should I add", improvements, new commands or tools, or planning before implementation. Outputs ranked proposals and stops for the user's choice; it does not implement.
---

# Feature ideation

Paths are relative to this skill directory.

## Workflow
1. Ground: run repo-map (skill `using-termux-skills`). Read the README and the definitions index; list existing commands, aliases, and tools by name. Check recent commit subjects and TODO/FIXME comments for direction. Infer the project's theme and audience from the code, not from assumptions.
2. Find gaps from evidence (sources below). Skip ideas the repository already covers; note overlaps instead.
3. Check feasibility of every candidate: needed packages exist in Termux (`pkg search`, or the Termux packages repository); Termux:API needs the add-on app plus the package; root is optional (propose a non-root path first); storage and background limits (`termux-environment`); works on aarch64.
4. Score 1-5: value, effort (low is better), risk (low is better), maintenance (low is better), Termux fit. Drop anything under 3 on value or Termux fit.
5. Present the top 3-5 using `assets/feature-brief.md`. Ask which to build. Do not implement before the choice; then implement through the routing of `using-termux-skills`.

## Idea sources (cite the evidence)
- Friction: repeated manual steps, long command lines typed often, missing flags, non-idempotent steps.
- Parity: standard Linux commands that Termux lacks or that behave differently.
- Unused capability: Termux:API commands, boot scripts, services, open/share integrations the project does not use yet (`references/termux-capabilities.md`).
- Quality: verification, backup and restore, diagnostics (`doctor`-style checks), safer defaults, startup speed.
- Ergonomics: extra keys, prompt info, completions, short commands for existing workflows.

## Quality bar
- Relevant to the project's purpose and style. Valuable: saves time, prevents errors, or enables something impossible now. Small: one feature is one command or module.
- Reject: duplicates; frameworks or large dependencies for small gains; root-only ideas unless the user says the device is rooted; private data or network use without explicit opt-in; cosmetic churn; anything that cannot be verified or maintained cheaply.
- Every proposal states how it would be tested and what could go wrong on Termux.

## Gotchas
- Never recommend a package without checking that Termux ships it for the user's architecture.
- Termux:API features need the add-on app and permissions; propose a fallback.
- Android may kill background work; do not promise reliability.
- A feature that shadows a system command is a wrapper: it keeps native behavior and output (no log prefixes).
- Fewer, better proposals beat a long list.
