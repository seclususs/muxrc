# Shell init patterns

Load when changing how the shell starts, prompts, completes, or loads modules.

## Discover before adding
Find the rc file, how it sources modules (search for `source`), and the load order; add new code as a module in that mechanism, not inline in the rc file.

## Module rules
- Guard against double sourcing; define functions only; no output, prompts, or slow work at source time.
- One concern per module; the loader decides order. Name modules by concern, not by feature.
- Aliases for fixed command lines; functions when arguments, conditions, or quoting matter. Replacing a system command is a wrapper: keep native behavior and output.

## Performance
- Measure: `time zsh -i -c exit`; profile with `zmodload zsh/zprof` at the top of the rc and `zprof` at the end.
- Remove `$(...)` and external commands from startup; test command presence with `(( $+commands[tool] ))`.
- Defer heavy plugins to first use (a stub function that sources the plugin, then calls it).
- Cache generated completion dumps and skip regeneration when fresh; compile large files with `zcompile`. Verify with the timing again.

## Prompt
Keep it a pure function of cheap state. Do not run git or network commands synchronously per prompt unless the user opted in and the cost is measured.

## Dotfile installation (idempotent)
```sh
link() { # src dst
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then return 0; fi
  if [ -e "$2" ] && [ ! -L "$2" ]; then mv "$2" "$2.bak.$(date +%Y%m%d%H%M%S)"; fi
  ln -sfn "$1" "$2"
}
```
Never overwrite a user file without a backup; keep sources in `$HOME` (symlinks in shared storage fail).

## Boot and background
Termux:Boot app (open once) runs scripts in `~/.termux/boot/`; start with `termux-wake-lock`; no prompts; log to a file under `$HOME`. Android may still kill background work (see `termux-environment`).
