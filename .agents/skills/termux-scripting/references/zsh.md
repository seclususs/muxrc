# zsh reference (Termux)

## Startup files (zsh manual, Files)
Order: `.zshenv` (every shell: no output, never assume a tty), `.zprofile` (login), `.zshrc` (interactive), `.zlogin` (login). `ZDOTDIR` defaults to `$HOME`; `zsh -f` skips them. Keep `.zshenv` minimal (variables non-interactive shells need); put interactive logic in `.zshrc` modules. Discover how the project loads modules (search for `source` in its rc file) before adding one.

## Module pattern
Guard against double sourcing; define functions only; no output, prompts, or slow work at source time (`assets/templates/zsh-module.zsh.tpl`).

## Function hygiene
- First line `emulate -L zsh` (localizes options, resets zsh defaults).
- `local`/`typeset` for variables; `typeset -g` for intended globals.
- Output with `print -r -- "$x"`, errors with `print -u2`; avoid `echo` (zsh expands escapes by default).
- Never name variables after special parameters: `path`, `status`, `argv`, `commands`, `functions`, `aliases`, `options`, `parameters`, `pipestatus`, `prompt`, `reply`, `fpath`, `cdpath`, `manpath`.
- Command exists without a fork: `(( $+commands[tool] ))`. shfmt may rewrite a hyphenated name inside `$+commands[...]`: review its diff.
- Sourced file path: `${(%):-%x}`; absolute: `${${(%):-%x}:A}` (`$BASH_SOURCE` does not exist).
- Unmatched glob is an error; `files=(*.x(N))` yields an empty array.
- No word splitting: use arrays, `${(s: :)v}`, or `${=v}`.
- Arrays are 1-indexed, `${a[-1]}` last, `${#a}` length.
- Indirect `${(P)name}`; eval-safe quoting `${(q)v}`; lines to array `${(@f)"$(cmd)"}`.
- Prompted read: `read 'v?prompt: '`. `cmd | while read` keeps variables.
- Hooks: `autoload -Uz add-zsh-hook; add-zsh-hook precmd fn`.

## Startup speed
Measure first: `time zsh -i -c exit`; `zmodload zsh/zprof` at the top of `.zshrc` and `zprof` at the end. Remove forks (`$(...)`) and external commands from startup, defer plugin loading, cache completion dumps, `zcompile` large files. Re-measure to confirm.

## Checks
`zsh -n file` (syntax), `zsh -f -c 'source file'` (load without rc interference), `trace-run` (skill `systematic-debugging`) for traces. ShellCheck does not support zsh; shfmt is diff-only (`shfmt -d FILE.zsh`, no flags).
