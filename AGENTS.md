# Agent Instructions

Rules and skills live in `.agents/` and are self-contained. This file only points to them.

- Rules (always on): `.agents/rules/core-policy.md`. If the environment does not load `.agents/rules/` by itself, read it first.
- Entry skill: `.agents/skills/using-termux-skills/SKILL.md`. It applies to every message, including questions; the entry gate is in the core policy.
