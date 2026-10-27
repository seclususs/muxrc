#!/bin/sh
# def-index.sh - index shell definitions and compare two indexes (static, nothing is executed).
# Kinds: func, alias, var (top-level), hook (add-zsh-hook), widget (zle -N), source.
set -u
LC_ALL=C
export LC_ALL

usage() {
  cat << 'EOF'
Usage: def-index.sh [options] [PATH ...]

Index mode (default): prints "kind<TAB>name<TAB>file:line" lines, sorted. Save a baseline with --out:
  def-index.sh --out .termux-agent/refactor/before.tsv
Compare mode: indexes the current files and compares them with a saved baseline:
  def-index.sh --compare .termux-agent/refactor/before.tsv [--rename OLD=NEW ...]
Reports: removed, added, moved (same name, different file set), renamed (declared with --rename),
duplicate (func or alias defined more often than in the baseline). Exit 1 on removed or duplicate.

Options:
  --out FILE       write the index to FILE (UTF-8, LF) instead of stdout
  --compare FILE   baseline index to compare against
  --rename OLD=NEW expected rename of a func, alias, or var (repeatable)
  --root DIR       run in this directory instead of the current one
  -h, --help       show this help

PATH arguments (files or directories) limit the scan. Without PATH, the scan covers git-tracked and
untracked, non-ignored files (or every file under the directory outside git), excluding .agent, .agents, and .termux-agent.
Detection is line-based: it finds definitions at the usual positions and does not evaluate code.
Dynamic definitions (eval, generated names) are not seen; verify them with behavior-snapshot.
Variables count only at column 0 (top level); definitions inside functions are not indexed.
Exit codes: 0 ok, 1 removed or duplicate found, 2 usage error.
EOF
}

die_usage() {
  echo "def-index: $1" >&2
  exit 2
}

compare=""
outfile=""
root=""
renames=""
nl='
'
paths=""
while [ $# -gt 0 ]; do
  case $1 in
    --out)
      [ $# -ge 2 ] || die_usage "--out needs a value"
      outfile=$2
      shift
      ;;
    --compare)
      [ $# -ge 2 ] || die_usage "--compare needs a value"
      compare=$2
      shift
      ;;
    --rename)
      [ $# -ge 2 ] || die_usage "--rename needs OLD=NEW"
      case $2 in
        ?*=?*) renames="${renames}${2%%=*}	${2#*=}${nl}" ;;
        *) die_usage "--rename needs OLD=NEW" ;;
      esac
      shift
      ;;
    --root)
      [ $# -ge 2 ] || die_usage "--root needs a value"
      root=$2
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*) die_usage "unknown option: $1" ;;
    *) paths="${paths}${1}${nl}" ;;
  esac
  shift
done
while [ $# -gt 0 ]; do
  paths="${paths}${1}${nl}"
  shift
done

if [ -n "${root}" ]; then
  cd "${root}" || die_usage "cannot enter --root directory"
fi
if [ -n "${compare}" ] && [ ! -f "${compare}" ]; then
  die_usage "baseline not found: ${compare}"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/def-index.XXXXXX") || die_usage "cannot create a temporary directory"
trap 'rm -rf "${tmp}"' EXIT INT TERM HUP

is_shell_name() {
  case ${1##*/} in
    *.sh | *.bash | *.zsh | *.ksh | .zshrc | .zshenv | .zprofile | .zlogin | .zlogout | .bashrc | .bash_profile | .bash_login | .profile) return 0 ;;
    *.*) return 1 ;;
  esac
  return 2
}

shebang_is_shell() {
  case $1 in
    '#!'*) ;;
    *) return 1 ;;
  esac
  # shellcheck disable=SC2046
  set -- $(printf '%s\n' "$1" | sed 's/^#![ 	]*//')
  interp=${1:-}
  interp=${interp##*/}
  if [ "${interp}" = env ]; then
    shift
    while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done
    interp=${1:-}
    interp=${interp##*/}
  fi
  case ${interp} in
    sh | bash | zsh | dash | ksh | ash | mksh | busybox) return 0 ;;
  esac
  return 1
}

list_candidates() {
  if [ -n "${paths}" ]; then
    printf '%s' "${paths}" | while IFS= read -r p; do
      [ -n "${p}" ] || continue
      if [ -d "${p}" ]; then
        find "${p}" \( -name .git -o -name .agent -o -name .agents -o -name .termux-agent -o -name node_modules \) -prune -o -type f -print
      elif [ -f "${p}" ]; then
        printf '%s\n' "${p}"
      else
        echo "def-index: not found: ${p}" >&2
      fi
    done
  elif git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -c core.quotepath=off ls-files -co --exclude-standard | grep -v -E '^(\.agents?|\.termux-agent)/'
  else
    find . \( -name .git -o -name .agent -o -name .agents -o -name .termux-agent -o -name node_modules \) -prune -o -type f -print | sed 's|^\./||'
  fi
}

build_index() { # build_index OUTFILE
  list_candidates | sort -u > "${tmp}/candidates"
  : > "${tmp}/files"
  while IFS= read -r f; do
    [ -f "${f}" ] || continue
    is_shell_name "${f}"
    rc=$?
    if [ "${rc}" -eq 0 ]; then
      printf '%s\n' "${f}" >> "${tmp}/files"
    elif [ "${rc}" -eq 2 ]; then
      first=$(head -n 1 "${f}" 2> /dev/null | tr -d '\000')
      shebang_is_shell "${first}" && printf '%s\n' "${f}" >> "${tmp}/files"
    fi
  done < "${tmp}/candidates"
  awk -f "${tmp}/index.awk" -v LIST="${tmp}/files" | sort > "$1"
}

cat > "${tmp}/index.awk" << 'EOF'
function emit(kind, name, f, ln) { if (name != "") printf "%s\t%s\t%s:%d\n", kind, name, f, ln }
function unquote(s) { sub(/^["']/, "", s); sub(/["']$/, "", s); return s }
function process(line, f, ln,    s, name, n, w, fn) {
  if (line ~ /^[ \t]*#/) return
  if (line ~ /^[ \t]*function[ \t]+[^ \t(){;]/) {
    s = line; sub(/^[ \t]*function[ \t]+/, "", s)
    match(s, /^[^ \t(){;]+/); emit("func", substr(s, 1, RLENGTH), f, ln); return
  }
  if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_.:+@-]*[ \t]*\(\)/)) {
    s = substr(line, 1, RLENGTH); sub(/^[ \t]*/, "", s); sub(/[ \t]*\(\)$/, "", s); emit("func", s, f, ln); return
  }
  if (line ~ /^[ \t]*alias[ \t]+/) {
    s = line; sub(/^[ \t]*alias[ \t]+/, "", s)
    while (s ~ /^-[A-Za-z]+[ \t]+/) sub(/^-[A-Za-z]+[ \t]+/, "", s)
    if (s ~ /=/) { name = s; sub(/=.*$/, "", name); name = unquote(name); if (name !~ /[ \t]/) emit("alias", name, f, ln) }
    return
  }
  if (line ~ /^[ \t]*add-zsh-hook[ \t]+/) {
    s = line; sub(/^[ \t]*add-zsh-hook[ \t]+/, "", s)
    if (s ~ /^-[A-Za-z]*[dD]/) return
    while (s ~ /^-[A-Za-z]+[ \t]+/) sub(/^-[A-Za-z]+[ \t]+/, "", s)
    n = split(s, w, /[ \t]+/)
    if (n >= 2) { fn = w[2]; sub(/[;&|].*$/, "", fn); emit("hook", w[1] ":" fn, f, ln) }
    return
  }
  if (line ~ /^[ \t]*zle[ \t]+-N[ \t]+/) {
    s = line; sub(/^[ \t]*zle[ \t]+-N[ \t]+/, "", s); n = split(s, w, /[ \t]+/); emit("widget", unquote(w[1]), f, ln); return
  }
  if (line ~ /^(export|readonly|typeset|declare)[ \t]+/) {
    s = line; sub(/^(export|readonly|typeset|declare)[ \t]+/, "", s)
    while (s ~ /^-[A-Za-z]+[ \t]+/) sub(/^-[A-Za-z]+[ \t]+/, "", s)
    if (match(s, /^[A-Za-z_][A-Za-z0-9_]*/)) emit("var", substr(s, 1, RLENGTH), f, ln)
    return
  }
  if (match(line, /^[A-Za-z_][A-Za-z0-9_]*[+]?=/)) {
    name = substr(line, 1, RLENGTH - 1); sub(/[+]$/, "", name); emit("var", name, f, ln); return
  }
  if (match(line, /(^|[;&|({]|then|do|else)[ \t]*(source|\.)[ \t]+[^ \t]+/)) {
    s = substr(line, RSTART, RLENGTH); n = split(s, w, /[ \t]+/); fn = w[n]; sub(/[;&|)}]+$/, "", fn); emit("source", fn, f, ln)
  }
}
BEGIN {
  while ((getline f < LIST) > 0) {
    ln = 0
    while ((getline line < f) > 0) { ln++; process(line, f, ln) }
    close(f)
  }
}
EOF

cat > "${tmp}/compare.awk" << 'EOF'
function addrec(arr, tag, k, f, loc) {
  if (!((tag, k, f) in seenf)) {
    seenf[tag, k, f] = 1
    fl[tag, k] = fl[tag, k] (fl[tag, k] == "" ? "" : ",") f
    nf[tag, k]++
  }
  cnt[tag, k]++
  if (!((tag, k) in first)) first[tag, k] = loc
  locs[tag, k] = locs[tag, k] (locs[tag, k] == "" ? "" : ",") loc
  arr[k] = 1
}
function samefiles(k,    i, n, a) {
  if (nf["b", k] != nf["c", k]) return 0
  n = split(fl["c", k], a, ",")
  for (i = 1; i <= n; i++) if (!(("b", k, a[i]) in seenf)) return 0
  return 1
}
function readidx(file, tag, arr,    line, a, k, f) {
  while ((getline line < file) > 0) {
    if (line == "" || line ~ /^#/) continue
    split(line, a, "\t"); k = a[1] SUBSEP a[2]; f = a[3]; sub(/:[0-9]+$/, "", f)
    addrec(arr, tag, k, f, a[3])
    total[tag]++
  }
  close(file)
}
BEGIN {
  while ((getline line < REN) > 0) { split(line, a, "\t"); if (a[1] != "") rn[a[1]] = a[2] }
  readidx(BASE, "b", b); readidx(CUR, "c", c)
  for (k in b) {
    split(k, p, SUBSEP); kind = p[1]; name = p[2]
    if ((name in rn) && (kind == "func" || kind == "alias" || kind == "var")) {
      nk = kind SUBSEP rn[name]
      if ((nk in c) && !(nk in b)) { printf "renamed %s %s -> %s (%s)\n", kind, name, rn[name], first["c", nk]; nren++; done[nk] = 1; continue }
    }
    if (!(k in c)) { printf "removed %s %s (%s)\n", kind, name, first["b", k]; nrem++; continue }
    if (!samefiles(k)) { printf "moved %s %s (%s -> %s)\n", kind, name, fl["b", k], fl["c", k]; nmov++ }
  }
  for (k in c) {
    split(k, p, SUBSEP); kind = p[1]; name = p[2]
    if (!(k in b) && !(k in done)) { printf "added %s %s (%s)\n", kind, name, first["c", k]; nadd++ }
    if ((kind == "func" || kind == "alias") && cnt["c", k] > 1 && cnt["c", k] > cnt["b", k]) { printf "duplicate %s %s (%s)\n", kind, name, locs["c", k]; ndup++ }
  }
  printf "#SUMMARY removed=%d added=%d moved=%d renamed=%d duplicate=%d base=%d current=%d\n", nrem, nadd, nmov, nren, ndup, total["b"], total["c"]
}
EOF

if [ -z "${compare}" ]; then
  if [ -n "${outfile}" ]; then
    build_index "${outfile}"
    echo "def-index: wrote $(awk 'END { print NR }' "${outfile}") entries to ${outfile}"
    exit 0
  fi
  build_index "${tmp}/current"
  cat "${tmp}/current"
  exit 0
fi

build_index "${tmp}/current"
printf '%s' "${renames}" > "${tmp}/renames"
awk -f "${tmp}/compare.awk" -v BASE="${compare}" -v CUR="${tmp}/current" -v REN="${tmp}/renames" > "${tmp}/report"
grep -v '^#SUMMARY' "${tmp}/report" | sort
summary=$(grep '^#SUMMARY' "${tmp}/report" | sed 's/^#//')
echo "${summary}"
case ${summary} in
  *"removed=0 "*"duplicate=0 "*) exit 0 ;;
esac
exit 1
