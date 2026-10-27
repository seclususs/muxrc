#!/bin/sh
# diff-collect.sh - write the complete git diff to disk and verify it against git statistics.
# Read-only for the repository: writes only under the output directory.
# Output: key=value lines and a manifest on stdout; the last line is END (missing END = truncated output).
set -u
LC_ALL=C
export LC_ALL

usage() {
  cat << 'EOF'
Usage: diff-collect.sh [options]

Writes the full diff to files so no pager, terminal buffer, or tool output limit can truncate it,
then checks the files against `git diff --numstat`.

Scope (default: working tree vs HEAD, staged + unstaged, plus untracked files):
  --staged             staged changes only (git diff --cached)
  --unstaged           unstaged changes plus untracked files
  --range A..B         commit range (A..B or A...B); untracked files are not included
Options:
  --out DIR            output directory (default: <root>/.termux-agent, inside the workspace);
                       a relative path starts at the repository root
  --context N          context lines per hunk (default 3)
  --chunk N            lines per read range printed in the read plan (default 250)
  --no-untracked       skip untracked files
  --include-agent      include .agent and .agents (excluded by default: agent tooling is not project code)
  --max-untracked-kb N untracked files larger than this are listed, not diffed (default 512)
  --root DIR           run in this directory instead of the current one
  -h, --help           show this help

Files written: tracked.diff, untracked.diff, MANIFEST.tsv
Manifest columns: part, status, add, del, first-line, last-line, path (lines refer to the part file).
Exit codes: 0 verified, 1 verification mismatch, 2 usage or not a git repository, 3 git failure.
EOF
}

die_usage() {
  echo "diff-collect: $1" >&2
  exit 2
}

need_num() {
  case $2 in
    '' | *[!0-9]*) die_usage "$1 needs a non-negative integer" ;;
  esac
}

scope=all
range=""
out=""
ctx=3
chunk=250
untracked=1
agent=0
maxkb=512
root=""
while [ $# -gt 0 ]; do
  case $1 in
    --staged) scope=staged ;;
    --unstaged) scope=unstaged ;;
    --range)
      [ $# -ge 2 ] || die_usage "--range needs a value"
      scope=range
      range=$2
      shift
      ;;
    --out)
      [ $# -ge 2 ] || die_usage "--out needs a value"
      out=$2
      shift
      ;;
    --context)
      [ $# -ge 2 ] || die_usage "--context needs a value"
      ctx=$2
      shift
      ;;
    --chunk)
      [ $# -ge 2 ] || die_usage "--chunk needs a value"
      chunk=$2
      shift
      ;;
    --no-untracked) untracked=0 ;;
    --include-agent) agent=1 ;;
    --max-untracked-kb)
      [ $# -ge 2 ] || die_usage "--max-untracked-kb needs a value"
      maxkb=$2
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
    *) die_usage "unknown option: $1" ;;
  esac
  shift
done
need_num --context "${ctx}"
need_num --chunk "${chunk}"
need_num --max-untracked-kb "${maxkb}"
[ "${chunk}" -gt 0 ] || die_usage "--chunk must be greater than 0"

command -v git > /dev/null 2>&1 || {
  echo "diff-collect: git not found on this host (see platform-detection)" >&2
  exit 3
}
if [ -n "${root}" ]; then
  cd "${root}" || die_usage "cannot enter --root directory"
fi
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die_usage "not inside a git work tree"
top=$(git rev-parse --show-toplevel) || exit 3
cd "${top}" || exit 3
gitdir=$(git rev-parse --absolute-git-dir) || exit 3
[ -n "${out}" ] || out="${top}/.termux-agent"
mkdir -p "${out}" || die_usage "cannot create output directory: ${out}"

GIT_PAGER="cat"
PAGER="cat"
export GIT_PAGER PAGER

g() { git --no-pager -c core.quotepath=off -c color.ui=never "$@"; }

dopts="--no-renames --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/"

pspec=""
[ "${agent}" -eq 1 ] || pspec=". :(exclude).agent :(exclude).agents"

case ${scope} in
  all)
    g rev-parse --verify -q HEAD > /dev/null 2>&1 || die_usage "no commits yet; use --staged or --unstaged"
    sargs=HEAD
    ;;
  staged) sargs=--cached ;;
  unstaged) sargs="" ;;
  range) sargs=${range} ;;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/diff-collect.XXXXXX") || die_usage "cannot create a temporary directory"
trap 'rm -rf "${tmp}"' EXIT INT TERM HUP

# shellcheck disable=SC2086
g diff ${dopts} -U"${ctx}" --output="${out}/tracked.diff" ${sargs} -- ${pspec} || {
  echo "diff-collect: git diff failed" >&2
  exit 3
}
# shellcheck disable=SC2086
g diff ${dopts} --numstat ${sargs} -- ${pspec} > "${tmp}/numstat" || exit 3
# shellcheck disable=SC2086
g diff ${dopts} --name-status ${sargs} -- ${pspec} > "${tmp}/names" || exit 3

: > "${out}/untracked.diff"
: > "${tmp}/ulist"
: > "${tmp}/skipped"
if [ "${untracked}" -eq 1 ] && { [ "${scope}" = all ] || [ "${scope}" = unstaged ]; }; then
  g ls-files --others --exclude-standard > "${tmp}/untracked.list" || exit 3
  limit=$((maxkb * 1024))
  while IFS= read -r f; do
    [ -n "${f}" ] || continue
    [ -d "${f}" ] && continue
    if [ "${agent}" -eq 0 ]; then
      case ${f} in .agent/* | .agents/* | .termux-agent/*) continue ;; esac
    fi
    case ${f} in
      '"'*)
        printf '%s\n' "${f}" >> "${tmp}/skipped"
        continue
        ;;
    esac
    size=$(wc -c < "${f}" 2> /dev/null | tr -d ' ')
    if [ -z "${size}" ] || [ "${size}" -gt "${limit}" ]; then
      printf '%s\n' "${f}" >> "${tmp}/skipped"
      continue
    fi
    # shellcheck disable=SC2086
    g diff ${dopts} -U"${ctx}" --no-index --output="${tmp}/one.diff" -- /dev/null "${f}" > /dev/null 2>&1
    cat "${tmp}/one.diff" >> "${out}/untracked.diff"
    printf '%s\n' "${f}" >> "${tmp}/ulist"
  done < "${tmp}/untracked.list"
fi

# scan FILE: one row per "diff --git" block: first-line, last-line, additions, deletions, binary-flag
scan() {
  awk '
    /^diff --git / {
      if (n > 0) printf "%d\t%d\t%d\t%d\t%d\n", start, NR - 1, add, del, bin
      n++; start = NR; add = 0; del = 0; bin = 0; inh = 0; next
    }
    n > 0 && /^@@ / { inh = 1; next }
    n > 0 && (/^Binary files / || /^GIT binary patch/) { bin = 1; next }
    n > 0 && inh {
      c = substr($0, 1, 1)
      if (c == "+") add++
      else if (c == "-") del++
    }
    END { if (n > 0) printf "%d\t%d\t%d\t%d\t%d\n", start, NR, add, del, bin }
  ' "$1"
}

scan "${out}/tracked.diff" > "${tmp}/scan.tracked"
scan "${out}/untracked.diff" > "${tmp}/scan.untracked"

# tracked rows: join name-status, numstat, and scan by order; compare counts
awk -F'\t' -v NAMES="${tmp}/names" -v NUMS="${tmp}/numstat" '
  BEGIN {
    while ((getline line < NAMES) > 0) { nn++; i = index(line, "\t"); st[nn] = substr(line, 1, i - 1); nm[nn] = substr(line, i + 1) }
    while ((getline line < NUMS) > 0) {
      nu++; split(line, a, "\t"); ad[nu] = a[1]; dl[nu] = a[2]
      pt[nu] = substr(line, length(a[1]) + length(a[2]) + 3)
    }
  }
  { ns++; s1[ns] = $1; s2[ns] = $2; sa[ns] = $3; sd[ns] = $4; sb[ns] = $5 }
  END {
    bad = 0; fa = 0; fd = 0; aligned = 1
    if (nn != nu || nn != ns) {
      bad++; aligned = 0
      printf "verify_error=tracked entry count differs (name-status=%d numstat=%d patch=%d); the patch file is incomplete or git output changed\n", nn, nu, ns > "/dev/stderr"
    }
    for (i = 1; i <= nn; i++) {
      if (ad[i] == "-") {
        if (aligned && sb[i] != 1) { bad++; printf "verify_error=binary file not marked binary in patch: %s\n", nm[i] > "/dev/stderr" }
      } else {
        fa += ad[i]; fd += dl[i]
        if (aligned && (ad[i] != sa[i] || dl[i] != sd[i])) {
          bad++
          printf "verify_error=count mismatch for %s (numstat +%s -%s, patch +%s -%s)\n", nm[i], ad[i], dl[i], sa[i], sd[i] > "/dev/stderr"
        }
      }
      printf "tracked\t%s\t%s\t%s\t%s\t%s\t%s\n", st[i], ad[i], dl[i], (aligned ? s1[i] : "?"), (aligned ? s2[i] : "?"), nm[i]
    }
    printf "#files=%d add=%d del=%d bad=%d\n", nn, fa, fd, bad
  }
' "${tmp}/scan.tracked" > "${tmp}/rows.tracked" 2> "${tmp}/verify.err"

# untracked rows: additions must equal the file line count
awk -F'\t' -v LIST="${tmp}/ulist" '
  BEGIN { while ((getline line < LIST) > 0) { nn++; nm[nn] = line } }
  { ns++; s1[ns] = $1; s2[ns] = $2; sa[ns] = $3; sd[ns] = $4; sb[ns] = $5 }
  END {
    bad = 0; fa = 0; aligned = 1
    if (nn != ns) {
      bad++; aligned = 0
      printf "verify_error=untracked entry count differs (list=%d patch=%d); the patch file is incomplete\n", nn, ns > "/dev/stderr"
    }
    for (i = 1; i <= nn; i++) {
      if (!aligned) { printf "untracked\t?\t?\t?\t?\t?\t%s\n", nm[i]; continue }
      cnt = 0
      if (sb[i] != 1) { while ((getline l < nm[i]) > 0) cnt++; close(nm[i]) }
      if (sb[i] == 1) { a = "-"; d = "-" } else {
        a = sa[i]; d = sd[i]; fa += a
        if (a != cnt || d != 0) { bad++; printf "verify_error=count mismatch for untracked %s (file lines %d, patch +%s -%s)\n", nm[i], cnt, a, d > "/dev/stderr" }
      }
      printf "untracked\t?\t%s\t%s\t%s\t%s\t%s\n", a, d, s1[i], s2[i], nm[i]
    }
    printf "#files=%d add=%d del=0 bad=%d\n", nn, fa, bad
  }
' "${tmp}/scan.untracked" > "${tmp}/rows.untracked" 2>> "${tmp}/verify.err"

skipped=0
: > "${tmp}/rows.skipped"
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  skipped=$((skipped + 1))
  printf 'skipped\t?\t-\t-\t-\t-\t%s\n' "${f}" >> "${tmp}/rows.skipped"
done < "${tmp}/skipped"

{
  grep -v '^#' "${tmp}/rows.tracked"
  grep -v '^#' "${tmp}/rows.untracked"
  cat "${tmp}/rows.skipped"
} > "${out}/MANIFEST.tsv"

stat_of() { # stat_of KEY LINE -> value of key=value in a "#..." summary line
  printf '%s\n' "$2" | tr ' ' '\n' | sed -n "s/^#\{0,1\}$1=//p" | head -n 1
}
tl=$(grep '^#' "${tmp}/rows.tracked")
ul=$(grep '^#' "${tmp}/rows.untracked")
t_files=$(stat_of files "${tl}")
t_add=$(stat_of add "${tl}")
t_del=$(stat_of del "${tl}")
t_bad=$(stat_of bad "${tl}")
u_files=$(stat_of files "${ul}")
u_add=$(stat_of add "${ul}")
u_bad=$(stat_of bad "${ul}")
bad=$((t_bad + u_bad))

lines_of() { awk 'END { print NR }' "$1"; }
bytes_of() { wc -c < "$1" | tr -d ' '; }
tracked_lines=$(lines_of "${out}/tracked.diff")
untracked_lines=$(lines_of "${out}/untracked.diff")

ranges() { # ranges LINES CHUNK
  awk -v n="$1" -v c="$2" 'BEGIN {
    s = 1; k = 0; o = ""
    while (s <= n) {
      e = s + c - 1; if (e > n) e = n
      o = o (k ? " " : "") s "-" e; s = e + 1; k++
      if (k >= 100) { o = o " ..."; break }
    }
    print o
  }'
}

echo "diff-collect scope=${scope} out=${out}"
echo "part=tracked.diff lines=${tracked_lines} bytes=$(bytes_of "${out}/tracked.diff")"
echo "part=untracked.diff lines=${untracked_lines} bytes=$(bytes_of "${out}/untracked.diff")"
echo "files=$((t_files + u_files)) tracked=${t_files} untracked=${u_files} skipped=${skipped} additions=$((t_add + u_add)) deletions=${t_del}"
if [ "${bad}" -eq 0 ]; then
  echo "verify=ok"
else
  echo "verify=mismatch"
  cat "${tmp}/verify.err"
fi
echo "chunk=${chunk}"
[ "${tracked_lines}" -gt 0 ] && echo "ranges tracked.diff: $(ranges "${tracked_lines}" "${chunk}")"
[ "${untracked_lines}" -gt 0 ] && echo "ranges untracked.diff: $(ranges "${untracked_lines}" "${chunk}")"
[ "${skipped}" -gt 0 ] && echo "skipped files (not diffed; read them directly in ranges): see MANIFEST.tsv rows with part=skipped"
echo "manifest=${out}/MANIFEST.tsv"
rows=$(awk 'END { print NR }' "${out}/MANIFEST.tsv")
if [ "${rows}" -gt 0 ]; then
  echo "rows (part status add del first last path):"
  head -n 60 "${out}/MANIFEST.tsv" | tr '\t' ' '
  [ "${rows}" -gt 60 ] && echo "... $((rows - 60)) more rows in MANIFEST.tsv"
fi
echo "END"
[ "${bad}" -eq 0 ] || exit 1
exit 0
