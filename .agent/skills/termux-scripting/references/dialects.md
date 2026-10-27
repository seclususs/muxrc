# Dialect matrix

Termux `sh` is dash (verify on device). (t) = tested here: dash 0.5.12, busybox ash 1.36, bash 5.2, zsh 5.9; other cells follow documented behavior.

| Feature | POSIX sh (dash) | bash | zsh |
|---|---|---|---|
| `[[ ]]` | no (t) | yes | yes |
| Arrays | no; use `set --` or newline lists | 0-indexed | 1-indexed; `${a[0]}` empty (t) |
| Associative arrays | no | `declare -A` | `typeset -A` |
| `local` | accepted, not POSIX (t) | yes | yes |
| `echo -e` | prints `-e` (t) | works | works |
| `echo "a\tb"` | tab (t) | literal `\t` (t) | tab (t) |
| `read -p prompt` | no | prompt | coprocess error (t) |
| `<<<`, `<(cmd)`, `$'..'`, `${v//a/b}` | no | yes | yes |
| `source`, `function f {}` | no; use `.`, `f() {}` | yes | yes |
| `pipefail` | dash >= 0.5.13 only; absent in 0.5.12 (t) | yes | yes |
| Unquoted `$var` splitting | yes | yes | no (t) |
| `cmd \| while read` variables | lost (t, also busybox) | lost (t) | kept (t) |
| `$LINENO` | empty in dash 0.5.12 (t); set in busybox ash (t) | yes | yes |
| Unmatched glob | stays literal (t) | literal | error `no matches found` (t); `(N)` qualifier |
| `set -e` in `a && b` | not triggered (t) | not triggered | not triggered |

Notes
- Repositories using bash shebangs keep bash for those files (`dialect.*` in repo-map). Start from the POSIX template and add bash features deliberately.
- bash to POSIX sh: `posix-sh.md`. bash to zsh: `zsh.md`.
