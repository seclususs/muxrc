#!/bin/sh
# repo-map.sh - compact, fact-only snapshot of a repository's shell/config layout.
# Read-only. Output: tagged lines on stdout. Use it instead of assuming paths.

set -u

usage() {
  cat << 'EOF'
Usage: repo-map.sh [--root DIR] [--max N] [-h|--help]

Snapshot of repository facts (read-only):
  root, git        repository root, branch@commit, dirty file count
  conf             known config files present (editorconfig, shellcheckrc, ...)
  dirs             file count per top-level directory
  files            total files and shell-like files
  dialect.*        shell-like files per dialect: posix | bash | zsh | other
  shebang          first-line forms and their counts
  loc.shell        total lines in shell-like files
  def              function/alias definitions as FILE:LINE KIND NAME (up to N)
  termux_cmds      termux-* commands referenced, with counts
  ext_cmds         external commands guarded by command -v / require_cmd
  logui.prefix     files containing [*] [+] [-] [!] [?] prefix tokens, with counts
  logui.calls      files calling log_info/success/warn/error/prompt, with counts
  commits          last 8 commit subjects (style reference)

Options:
  --root DIR   repository root (default: git toplevel, else current directory)
  --max N      cap definition lines (default 80)

Exit codes: 0 ok, 2 usage error or unreadable root.
EOF
}

root=""
max=80
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --root)
      if [ $# -lt 2 ]; then
        echo "repo-map: --root needs a value" >&2
        exit 2
      fi
      root=$2
      shift 2
      ;;
    --max)
      if [ $# -lt 2 ]; then
        echo "repo-map: --max needs a value" >&2
        exit 2
      fi
      max=$2
      shift 2
      ;;
    *)
      echo "repo-map: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done
case ${max} in
  '' | *[!0-9]*)
    echo "repo-map: --max must be a number" >&2
    exit 2
    ;;
esac

if [ -z "${root}" ]; then
  root=$(git rev-parse --show-toplevel 2> /dev/null || pwd)
fi
if ! cd "${root}" 2> /dev/null; then
  echo "repo-map: cannot enter root: ${root}" >&2
  exit 2
fi
root=$(pwd)

tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/repo-map.$$")
mkdir -p "${tmp}"
trap 'rm -rf "${tmp}"' EXIT INT TERM

# File inventory: tracked + untracked-not-ignored via git, else find.
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  git -c core.quotepath=off ls-files -co --exclude-standard > "${tmp}/all.list" 2> /dev/null
else
  find . -type f ! -path './.git/*' 2> /dev/null | sed 's|^\./||' > "${tmp}/all.list"
fi

# The agent tooling directory is not project code; leave it out of the facts.
awk '!/^\.agents?\// && !/^\.artifacts\//' "${tmp}/all.list" > "${tmp}/all.filtered"
mv "${tmp}/all.filtered" "${tmp}/all.list"

cr=$(printf '\r')

# Dialect of a shebang line: prints posix | bash | zsh | other
shebang_dialect() {
  set -f
  # shellcheck disable=SC2086
  set -- ${1#\#!}
  set +f
  interp=${1:-}
  interp=${interp##*/}
  if [ "${interp}" = "env" ]; then
    shift
    while [ $# -gt 0 ]; do
      case $1 in
        -* | *=*) shift ;;
        *) break ;;
      esac
    done
    interp=${1:-}
    interp=${interp##*/}
  fi
  case ${interp} in
    sh | dash | ash) echo posix ;;
    bash) echo bash ;;
    zsh) echo zsh ;;
    *) echo other ;;
  esac
}

: > "${tmp}/posix.list"
: > "${tmp}/bash.list"
: > "${tmp}/zsh.list"
: > "${tmp}/other.list"
: > "${tmp}/shebang.list"
while IFS= read -r f; do
  [ -f "${f}" ] || continue
  base=${f##*/}
  first=""
  case ${base} in
    *.sh | *.bash | *.zsh | *.ksh | .zshrc | .zshenv | .zprofile | .zlogin | .bashrc | .bash_profile | .profile)
      IFS= read -r first 2> /dev/null < "${f}" || first=""
      first=${first%"${cr}"}
      ;;
    *.*) continue ;;
    *)
      IFS= read -r first 2> /dev/null < "${f}" || first=""
      first=${first%"${cr}"}
      case ${first} in
        '#!'*) ;;
        *) continue ;;
      esac
      ;;
  esac
  case ${first} in
    '#!'*)
      d=$(shebang_dialect "${first}")
      printf '%s\n' "${first}" >> "${tmp}/shebang.list"
      ;;
    *)
      case ${base} in
        *.zsh | .zshrc | .zshenv | .zprofile | .zlogin) d=zsh ;;
        *.bash | .bashrc | .bash_profile) d=bash ;;
        *) d=posix ;;
      esac
      ;;
  esac
  printf '%s\n' "${f}" >> "${tmp}/${d}.list"
done < "${tmp}/all.list"
cat "${tmp}/posix.list" "${tmp}/bash.list" "${tmp}/zsh.list" "${tmp}/other.list" > "${tmp}/shell.list"

echo "root=${root}"
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  br=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || echo unknown)
  sha=$(git rev-parse --short HEAD 2> /dev/null || echo none)
  dirty=$(git status --porcelain -- . ':(exclude).agent' ':(exclude).agents' 2> /dev/null | wc -l | tr -d ' ')
  echo "git=${br}@${sha} dirty=${dirty}"
else
  echo "git=none"
fi

conf=""
for c in .editorconfig .shellcheckrc .gitattributes .gitignore .gitmodules .github Makefile README.md; do
  [ -e "${c}" ] && conf="${conf} ${c}"
done
echo "conf=${conf# }"

awk -F/ 'NF > 1 { c[$1]++ } NF == 1 { c["."]++ } END { for (k in c) print k ":" c[k] }' "${tmp}/all.list" | LC_ALL=C sort | tr '\n' ' ' | sed 's/^/dirs=/; s/ $//'
echo
echo "files=$(wc -l < "${tmp}/all.list" | tr -d ' ') shell=$(wc -l < "${tmp}/shell.list" | tr -d ' ')"
for d in posix bash zsh other; do
  n=$(wc -l < "${tmp}/${d}.list" | tr -d ' ')
  echo "dialect.${d}=${n}"
done
if [ -s "${tmp}/shebang.list" ]; then
  LC_ALL=C sort "${tmp}/shebang.list" | uniq -c | LC_ALL=C sort -k1,1nr -k2 | awk '{ n = $1; $1 = ""; sub(/^ /, ""); print "shebang=" $0 " (" n ")" }'
fi

# One awk pass over shell-like files: definitions, counts, loc.
awk -v LIST="${tmp}/shell.list" -v MAX="${max}" '
BEGIN {
  WS = "[ " "\t" "]"
  NM = "[A-Za-z_][A-Za-z0-9_:.-]*"
  Q = sprintf("%c", 39)
  LUPAT = "(^|[^A-Za-z0-9_])\\[[*+!?-]\\]([^}]|$)"
  LCPAT = "(^|[^A-Za-z0-9_])log_(info|success|warn|error|prompt)([^A-Za-z0-9_]|$)"
  loc = 0
  ndef = 0
  while ((getline file < LIST) > 0) {
    n = 0
    lc = 0
    cc = 0
    while ((getline line < file) > 0) {
      n++
      loc++
      if (line ~ "^" WS "*#") continue
      if (match(line, "^" WS "*(function" WS "+)?" NM WS "*\\(\\)")) {
        nm = substr(line, RSTART, RLENGTH)
        sub("^" WS "*(function" WS "+)?", "", nm)
        sub(WS "*\\(\\)$", "", nm)
        kind = "func"
      } else if (match(line, "^" WS "*function" WS "+" NM)) {
        nm = substr(line, RSTART, RLENGTH)
        sub("^" WS "*function" WS "+", "", nm)
        kind = "func"
      } else if (match(line, "^" WS "*alias" WS "+(-[a-zA-Z]+" WS "+)?" NM "=")) {
        nm = substr(line, RSTART, RLENGTH)
        sub("^" WS "*alias" WS "+(-[a-zA-Z]+" WS "+)?", "", nm)
        sub("=$", "", nm)
        kind = "alias"
      } else {
        nm = ""
      }
      if (nm != "") {
        ndef++
        if (ndef <= MAX) print "def " file ":" n " " kind " " nm
      }
      s = line
      while (match(s, /termux-[a-z][a-z-]*/)) {
        tc[substr(s, RSTART, RLENGTH)]++
        s = substr(s, RSTART + RLENGTH)
      }
      s = line
      while (match(s, /(command -v|require_cmd)[ ]+[^ ;|&)(]+/)) {
        w = substr(s, RSTART, RLENGTH)
        sub(/^(command -v|require_cmd)[ ]+/, "", w)
        gsub(Q, "", w)
        gsub("\"", "", w)
        if (w ~ /^[A-Za-z0-9_.-]+$/) ec[w]++
        s = substr(s, RSTART + RLENGTH)
      }
      if (line ~ LUPAT) lc++
      if (nm == "" && line ~ LCPAT) cc++
    }
    close(file)
    if (lc > 0) lu[file] = lc
    if (cc > 0) cu[file] = cc
  }
  if (ndef > MAX) print "def ... " (ndef - MAX) " more (use --max)"
  print "loc.shell=" loc
  for (k in tc) print "T " k " " tc[k]
  for (k in ec) print "E " k " " ec[k]
  for (k in lu) print "L " k ":" lu[k]
  for (k in cu) print "C " k ":" cu[k]
}' > "${tmp}/awk.out"

grep '^loc.shell=' "${tmp}/awk.out"
grep '^def ' "${tmp}/awk.out"
printf 'termux_cmds='
grep '^T ' "${tmp}/awk.out" | LC_ALL=C sort -k3,3nr -k2,2 | awk '{ printf "%s%s(%s)", (NR > 1 ? " " : ""), $2, $3 }'
echo
printf 'ext_cmds='
grep '^E ' "${tmp}/awk.out" | LC_ALL=C sort -k3,3nr -k2,2 | awk '{ printf "%s%s(%s)", (NR > 1 ? " " : ""), $2, $3 }'
echo
printf 'logui.prefix='
grep '^L ' "${tmp}/awk.out" | LC_ALL=C sort | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $2 }'
echo
printf 'logui.calls='
grep '^C ' "${tmp}/awk.out" | LC_ALL=C sort | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $2 }'
echo

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "commits:"
  git log -n 8 --format='  %s' 2> /dev/null
fi
exit 0
