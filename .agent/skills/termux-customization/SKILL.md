---
name: termux-customization
description: Customizes and personalizes Termux - termux.properties, extra keys, colors, fonts, prompt, aliases, shell init modules, completion, startup speed, boot workflow. Use when asked to theme, tweak, personalize, or speed up the Termux environment or shell, or when editing *.properties, dircolors, nanorc, prompt, or plugin configuration. Not for brainstorming new features (feature-ideation).
---

# Termux customization

Paths are relative to this skill directory. Code goes through `termux-scripting`; runtime facts through `termux-environment`.

## Workflow
1. Facts: run repo-map (skill `using-termux-skills`); read the existing config and how the shell loads modules. Do not assume file locations.
2. Place the change (table below). One concern per file; extend, do not duplicate.
3. Edit minimally, keeping the existing style and banner comments.
4. Validate: `sh scripts/check-termux-config.sh FILE...` (or `.ps1`) for `.properties`; the lint gate for shell code.
5. Install idempotently: symlink with `ln -sfn`; back up an existing user file before replacing it; never overwrite user config silently.
6. Tell the user how to apply it on the device (`termux-reload-settings`, new session, or app restart) and what you could not verify.

## Where a change belongs
| Goal | Place | Apply |
|---|---|---|
| Extra keys, cursor, bell, keyboard, fullscreen | `~/.termux/termux.properties` | `termux-reload-settings` (some need an app restart) |
| Colors | `~/.termux/colors.properties` | `termux-reload-settings` |
| Font | `~/.termux/font.ttf` | `termux-reload-settings` |
| Aliases, functions, prompt, completion | zsh module sourced by `.zshrc` | new shell |
| Variables needed by all shells | `.zshenv` (minimal) | new shell |
| Command that must behave like a system command | wrapper (native output, no log prefixes) | new shell |
| Run at device boot | script in `~/.termux/boot/` (Termux:Boot app) | reboot; script in `$HOME`, executable |
| Long-running service | `termux-services` | per its docs |

## Rules
- Output contract by code role (core policy): utilities that print status use the project's logger convention; wrappers and external-CLI integrations have no prefixes and keep native output.
- Startup speed: measure first (`termux-scripting` `references/zsh.md`), remove forks from startup, defer heavy plugins, cache completion; report before and after timings.
- Keep the prompt cheap: no blocking git or network calls on every prompt.
- `allow-external-apps` lets other apps run commands in Termux: security-sensitive; change it only on explicit request.
- Prefer a few durable options over large themes; every added option must earn its place.

## Gotchas
- `.properties` is Java Properties text: a trailing space is part of the value (`true ` is not `true`), a trailing backslash continues the line, `#` and `!` start comments, CR bytes join the values.
- The format cannot reject unknown keys: a typo does nothing visible. Check spelling against `references/termux-properties.md`.
- `extra-keys` is a nested array: rows of strings or `{key: 'X', popup: {...}}` objects. Check bracket and quote balance (the validator does).
- Colors are `#RGB` or `#RRGGBB`; slots: `color0`-`color15`, `foreground`, `background`, `cursor`.
- Shared storage cannot hold files that must be executable or symlinked; keep config in `$HOME`.
- The Termux:Styling add-on app can overwrite colors and font; tell the user manual edits may be replaced.
- The key table snapshots the official template and can lag: an unknown-key WARN means verify against the Termux wiki, not wrong.
- Boot scripts run without a terminal: no prompts, no `tty` assumptions, call `termux-wake-lock` first when work must continue.
