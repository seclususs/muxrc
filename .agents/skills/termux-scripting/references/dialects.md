# Dialect matrix

Termux `sh` is dash (verify on device). (t) = tested here: dash 0.5.12 and 0.5.13.5 (built from the upstream tarball), busybox ash 1.36.1, bash 5.2, zsh 5.9; other cells follow documented behavior.

| Feature | POSIX sh (dash) | bash | zsh |
|---|---|---|---|
| `[[ ]]` | no: `[[: not found` at run time, `dash -n` accepts it (t) | yes | yes |
| Arrays | no; use `set --` or newline lists | 0-indexed | 1-indexed; `${a[0]}` empty (t) |
| Associative arrays | no | `declare -A` | `typeset -A` |
| `local` | accepted, not POSIX (t) | yes | yes |
| `echo -e` | prints `-e` (t) | works | works |
| `echo "a\tb"` | tab (t) | literal `\t` (t) | tab (t) |
| `read -p prompt` | not POSIX (`-r` only); dash accepts it (t) | prompt | coprocess error (t) |
| `<<<`, `<(cmd)`, `$'..'`, `${v//a/b}` | no: `<<<` and `<()` are parse errors, `${v//a/b}` fails at run time; `$'..'` is literal text in dash 0.5.12 and expanded in 0.5.13.5 (t) | yes | yes |
| `cmd &> f` | no: runs `cmd` in the background, output not redirected, creates an empty `f` (t) | yes | yes |
| `source`, `function f {}` | no; use `.`, `f() {}` | yes | yes |
| `pipefail` | absent in dash 0.5.12 (t), present in 0.5.13.5 (t) | yes | yes |
| Unquoted `$var` splitting | yes | yes | no (t) |
| `cmd \| while read` variables | lost (t, also busybox) | lost (t) | kept (t) |
| `$LINENO` | empty in dash 0.5.12 (t); set in dash 0.5.13.5 and busybox ash (t) | yes | yes |
| Unmatched glob | stays literal (t) | literal | error `no matches found` (t); `(N)` qualifier |
| `set -e` in `a && b` | not triggered (t) | not triggered | not triggered |

Notes
- Repositories using bash shebangs keep bash for those files (`dialect.*` in repo-map). Start from the POSIX template and add bash features deliberately.
- bash to POSIX sh: `posix-sh.md`. bash to zsh: `zsh.md`.
