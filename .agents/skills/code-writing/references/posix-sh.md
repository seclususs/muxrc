# POSIX sh reference (Termux dash)

## Replace bashisms
| Instead of | Use |
|---|---|
| `[[ $a == b* ]]` | `case $a in b*) ... ;; esac` |
| `[ a == b ]` | `[ a = b ]` |
| `${v//a/b}`, `${v:1:2}` | `sed`, `case`, or trims `${v#p}` `${v%s}` |
| arrays | `set -- "$@" item`; newline lists read with `while IFS= read -r` |
| `echo -e`, `echo -n` | `printf '%s\n'`, `printf '%s'` |
| `read -p "x"` | `printf 'x' >&2; read -r v` |
| `source f` | `. f` |
| `function f { }` | `f() { }` |
| `cmd &> f` | `cmd > f 2>&1` |
| `<<< "$s"` | `printf '%s\n' "$s" \| cmd` or a here-document |
| `<(cmd)` | temp file or pipe |
| `(( i++ ))` | `i=$((i + 1))` |
| `$RANDOM`, `$EUID`, `$OSTYPE` | `$$`, `$(id -u)`, `uname -s` |
| `local -r`, `declare` | `local`, `readonly` |
| `set -o pipefail` | `(set -o pipefail) 2>/dev/null && set -o pipefail` |
| `trap ... ERR` | `trap ... EXIT` plus explicit status checks |

## Patterns
```sh
# Arguments
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
  shift
done

# Numeric check
case $n in '' | *[!0-9]*) die "not a number: $n" ;; esac

# Capture and check
out=$(cmd) || die "cmd failed"

# Strip a CR (works in every dash; $'\r' needs a dash newer than 0.5.12)
cr=$(printf '\r'); v=${v%"${cr}"}

# Variables out of a loop: avoid the pipe subshell
cmd > "${tmp}/out"
while IFS= read -r line; do count=$((count + 1)); done < "${tmp}/out"

# Idempotent append
grep -qxF "$line" "$file" 2> /dev/null || printf '%s\n' "$line" >> "$file"

# Termux detection
[ -n "${TERMUX_VERSION:-}" ] && echo "running in Termux"
```
Quote `"${var}"`, put `--` before operands, use `<< 'EOF'` for literal here-documents, prefer `command -v` over `which`.
