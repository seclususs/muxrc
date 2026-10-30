#!/bin/sh
# lint-shell.sh - host-side quality gate for shell code that targets Termux.
# Read-only. Uses ShellCheck/shfmt/shell syntax checks when present and falls
# back to built-in heuristics (patterns.tsv) when a tool is missing.

set -u

here=$(cd "$(dirname "$0")" && pwd)
rules="${here}/patterns.tsv"
wrappers="${here}/wrapper-names.txt"

usage() {
  cat << 'EOF'
Usage: lint-shell.sh [options] [PATH ...]

Quality gate for shell code targeting Termux:
  sh/bash  ShellCheck + shfmt (project .editorconfig) + syntax check
  zsh      zsh -n only (ShellCheck unsupported; shfmt can corrupt zsh syntax)
  all      built-in heuristics: line endings, banner borders, bashisms,
           zsh pitfalls, Termux path/command compatibility, log-prefix scope
No PATH: lints the shell-like files of the repository (agent dirs excluded).

Options:
  --dialect D        force dialect: posix | bash | zsh (default: auto)
  --root DIR         project root (default: git toplevel, else current dir)
  --no-external      skip ShellCheck/shfmt/syntax tools (heuristics only)
  --strict           exit 1 on WARN as well
  --max-per-rule N   cap findings per rule per file (default 5)
  --list             print DIALECT<TAB>FILE for each file that would be linted, then exit
                     (used by format-shell.sh)
  --out FILE         write the findings to FILE (UTF-8, LF) and print only the
                     SUMMARY line; use for output longer than about 200 lines
                     (convention: .artifacts/lint/report.txt at the project root)
  -h, --help         show this help

Output: LEVEL FILE:LINE [CODE] message, then one SUMMARY line.
  LEVEL: ERROR | WARN | INFO | NOTE | SKIP
Exit: 0 no ERROR (and no WARN with --strict), 1 findings, 2 usage error.
Suppress a heuristic on one line with a trailing comment: lint-ignore: CODE
L002 flags log prefixes inside wrapper-like functions; names: scripts/wrapper-names.txt
ShellCheck notes count as WARN (judge new findings in changed files).
EOF
}

tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/lint-shell.$$")
mkdir -p "${tmp}"
trap 'rm -rf "${tmp}"' EXIT INT TERM
: > "${tmp}/args.list"

dialect_force=""
root=""
external=1
strict=0
maxper=5
outfile=""
list_only=0
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --dialect)
      [ $# -ge 2 ] || {
        echo "lint-shell: --dialect needs a value" >&2
        exit 2
      }
      dialect_force=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || {
        echo "lint-shell: --root needs a value" >&2
        exit 2
      }
      root=$2
      shift 2
      ;;
    --max-per-rule)
      [ $# -ge 2 ] || {
        echo "lint-shell: --max-per-rule needs a value" >&2
        exit 2
      }
      maxper=$2
      shift 2
      ;;
    --out)
      [ $# -ge 2 ] || {
        echo "lint-shell: --out needs a value" >&2
        exit 2
      }
      outfile=$2
      case ${outfile} in /*) ;; *) outfile="$(pwd)/${outfile}" ;; esac
      shift 2
      ;;
    --list)
      list_only=1
      shift
      ;;
    --no-external)
      external=0
      shift
      ;;
    --strict)
      strict=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "lint-shell: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      printf '%s\n' "$1" >> "${tmp}/args.list"
      shift
      ;;
  esac
done
while [ $# -gt 0 ]; do
  printf '%s\n' "$1" >> "${tmp}/args.list"
  shift
done
case ${dialect_force} in
  '' | posix | bash | zsh) ;;
  *)
    echo "lint-shell: --dialect must be posix, bash, or zsh" >&2
    exit 2
    ;;
esac
case ${maxper} in
  '' | *[!0-9]*)
    echo "lint-shell: --max-per-rule must be a number" >&2
    exit 2
    ;;
esac
if [ ! -f "${rules}" ]; then
  echo "lint-shell: rules file missing: ${rules}" >&2
  exit 2
fi

have() { command -v "$1" > /dev/null 2>&1; }
cr=$(printf '\r')

# Dialect of a shebang line: posix | bash | zsh | other
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

detect_dialect() {
  first=""
  IFS= read -r first 2> /dev/null < "$1" || true
  first=${first%"${cr}"}
  case ${first} in
    '#!'*)
      shebang_dialect "${first}"
      return
      ;;
  esac
  case ${1##*/} in
    *.zsh | .zshrc | .zshenv | .zprofile | .zlogin) echo zsh ;;
    *.bash | .bashrc | .bash_profile) echo bash ;;
    *.sh | *.ksh | .profile) echo posix ;;
    *) echo other ;;
  esac
}

# Tool availability and fallbacks
posix_sh=""
if have dash; then
  posix_sh=dash
elif have busybox && busybox sh -c ':' > /dev/null 2>&1; then
  posix_sh=busybox
elif have sh; then
  posix_sh="sh"
fi
posix_syntax() {
  case ${posix_sh} in
    dash) dash -n "$1" 2>&1 ;;
    busybox) busybox sh -n "$1" 2>&1 ;;
    *) sh -n "$1" 2>&1 ;;
  esac
}

out="${tmp}/out"
: > "${out}"
skipped=""
skip_once() {
  case " ${skipped} " in
    *" $1 "*) return ;;
  esac
  skipped="${skipped} $1"
  echo "SKIP $1: $2" >> "${out}"
}

has_editorconfig() {
  d=$(cd "$(dirname "$1")" && pwd)
  while :; do
    [ -f "${d}/.editorconfig" ] && return 0
    [ "${d}" = "/" ] && return 1
    d=$(dirname "${d}")
  done
}

# Heuristic pass: one awk process per file; rules come from patterns.tsv.
# shellcheck disable=SC2016
awk_prog='
function emit(level, ln, code, msg) { # lint-ignore: B002
  printf "%s %s:%d [%s] %s\n", level, F, ln, code, msg
}
function emitcap(level, ln, code, msg) { # lint-ignore: B002
  cnt[code]++
  if (cnt[code] <= MAXP) emit(level, ln, code, msg)
}
function iswrapper(name,   k) { # lint-ignore: B002
  if (name in wn) return 1
  for (k = 1; k <= npre; k++) {
    if (substr(name, 1, length(wpre[k])) == wpre[k]) return 1
  }
  return 0
}
function l002(ln, fn) { # lint-ignore: B002
  emitcap("WARN", ln, "L002", "UI log prefix inside wrapper-like function " fn ": wrappers and CLI integrations keep native output (no prefixes)")
}
BEGIN {
  WS = "[ " "\t" "]"
  nr = 0
  while ((getline rl < RULES) > 0) {
    if (rl ~ /^#/ || rl ~ /^[ ]*$/) continue
    if (split(rl, fld, "\t") < 5) continue
    nr++
    rd[nr] = "," fld[1] ","
    rs[nr] = fld[2]
    rc[nr] = fld[3]
    rx[nr] = fld[4]
    rm[nr] = fld[5]
  }
  close(RULES)
  NM = "[A-Za-z_][A-Za-z0-9_:.-]*"
  FNRE1 = "^" WS "*(function" WS "+)?" NM WS "*\\(\\)"
  FNRE2 = "^" WS "*function" WS "+" NM
  LUPAT = "(^|[^A-Za-z0-9_])\\[[*+!?-]\\]([^}]|$)"
  LCPAT = "(^|[^A-Za-z0-9_])log_(info|success|warn|error|prompt)([^A-Za-z0-9_]|$)"
  npre = 0
  while ((getline wl < WRAPPERS) > 0) {
    sub(/#.*/, "", wl)
    gsub("[ " "\t" "\r" "]", "", wl)
    if (wl == "" || wl == "*") continue
    if (substr(wl, length(wl)) == "*") {
      npre++
      wpre[npre] = substr(wl, 1, length(wl) - 1)
    } else {
      wn[wl] = 1
    }
  }
  close(WRAPPERS)
  infn = ""
  Q = sprintf("%c", 39)
  HDPAT = "(^|[^<])<<-?[ ]*[\"" Q "\\\\]?[A-Za-z_][A-Za-z0-9_]*"
  HDSTRIP = "[ \"" Q "\\\\]"
  inhd = 0
  p1 = ""
  p2 = ""
  crn = 0
  crfirst = 0
}
{
  line = $0
  if (index(line, "\r") > 0) {
    crn++
    if (crfirst == 0) crfirst = NR
  }
  if (line ~ (WS "+$")) emitcap("WARN", NR, "W001", "trailing whitespace")
  if (line ~ /^#+$/ && length(line) >= 3 && p1 ~ /^# / && p2 ~ /^#+$/ && length(p2) >= 3 && p1 !~ /[^ -~]/) {
    if (length(p2) != length(p1) || length(line) != length(p1)) {
      emit("WARN", NR - 2, "C001", "banner borders " length(p2) "/" length(line) " must equal title length " length(p1))
    }
  }
  p2 = p1
  p1 = line
  if (inhd) {
    cmp = line
    sub(/\r$/, "", cmp)
    if (hdtab) sub(/^\t+/, "", cmp)
    if (cmp == hdterm) inhd = 0
    next
  }
  if (NR == 1 && line ~ /^#!/) next
  if (line ~ /^[ ]*#/) next
  for (i = 1; i <= nr; i++) {
    if (index(rd[i], "," D ",") == 0 && index(rd[i], ",*,") == 0) continue
    if (line !~ rx[i]) continue
    if (index(line, "lint-ignore") > 0 && index(line, rc[i]) > 0) continue
    if (rs[i] == "COUNT") {
      lc[i]++
      if (lc[i] == 1) lf[i] = NR
      continue
    }
    emitcap(rs[i], NR, rc[i], rm[i])
  }
  lg = (index(line, "lint-ignore") > 0 && index(line, "L002") > 0)
  if (infn == "") {
    fname = ""
    if (match(line, FNRE1)) {
      fname = substr(line, RSTART, RLENGTH)
      sub("^" WS "*(function" WS "+)?", "", fname)
      sub(WS "*\\(\\)$", "", fname)
    } else if (match(line, FNRE2)) {
      fname = substr(line, RSTART, RLENGTH)
      sub("^" WS "*function" WS "+", "", fname)
    }
    if (fname != "") {
      wrap = iswrapper(fname)
      if (wrap && !lg && (line ~ LUPAT || line ~ LCPAT)) l002(NR, fname)
      if (line !~ /\{.*\}[ ]*(#.*)?$/) {
        infn = fname
        fnwrap = wrap
        fnind = match(line, /[^ ]/) - 1
        fnend = "^"
        for (k = 0; k < fnind; k++) fnend = fnend " "
        fnend = fnend "\\}[ ]*(#.*)?$"
      }
    }
  } else {
    if (fnwrap && !lg && (line ~ LUPAT || line ~ LCPAT)) l002(NR, infn)
    if (line ~ fnend) infn = ""
  }
  if (line !~ /\(\(/ && match(line, HDPAT)) {
    hd = substr(line, RSTART, RLENGTH)
    sub(/^[^<]*<</, "", hd)
    hdtab = (substr(hd, 1, 1) == "-")
    if (hdtab) hd = substr(hd, 2)
    gsub(HDSTRIP, "", hd)
    hdterm = hd
    hdline = NR
    inhd = 1
  }
}
END {
  for (i = 1; i <= nr; i++) {
    if (cnt[rc[i]] > MAXP && !(rc[i] in shown)) {
      shown[rc[i]] = 1
      printf "NOTE %s [%s] %d more finding(s) suppressed (raise --max-per-rule)\n", F, rc[i], cnt[rc[i]] - MAXP
    }
  }
  if (cnt["W001"] > MAXP) printf "NOTE %s [W001] %d more finding(s) suppressed (raise --max-per-rule)\n", F, cnt["W001"] - MAXP
  if (cnt["L002"] > MAXP) printf "NOTE %s [L002] %d more finding(s) suppressed (raise --max-per-rule)\n", F, cnt["L002"] - MAXP
  if (crn > 0) emit("ERROR", crfirst, "E001", "CR byte in " crn " line(s); LF line endings required")
  if (inhd) emit("WARN", hdline, "H001", "here-document delimiter " hdterm " never closed; later lines were not checked")
  for (i = 1; i <= nr; i++) {
    if (lc[i] > 0) emit("INFO", lf[i], rc[i], lc[i] " line(s): " rm[i])
  }
}'

lint_file() {
  f=$1
  d=$2
  first=""
  IFS= read -r first 2> /dev/null < "${f}" || true
  first=${first%"${cr}"}
  hasbang=0
  case ${first} in
    '#!'*)
      hasbang=1
      case ${first} in
        '#!/bin/'* | '#!/usr/'*)
          echo "INFO ${f}:1 [S003] FHS shebang resolves in Termux only via termux-exec; follow the project convention" >> "${out}"
          ;;
      esac
      ;;
    *)
      [ "${d}" = zsh ] || echo "INFO ${f}:1 [S001] no shebang (sourced/library file assumed)" >> "${out}"
      ;;
  esac
  if [ -s "${f}" ]; then
    last=$(tail -c 1 "${f}" | od -An -c | tr -d ' ')
    [ "${last}" = '\n' ] || echo "WARN ${f}:1 [E002] no newline at end of file" >> "${out}"
  fi
  awk -v F="${f}" -v D="${d}" -v RULES="${rules}" -v WRAPPERS="${wrappers}" -v MAXP="${maxper}" "${awk_prog}" "${f}" >> "${out}"

  [ "${external}" -eq 1 ] || return 0
  case ${d} in
    posix | bash)
      if have shellcheck; then
        if [ "${hasbang}" -eq 1 ]; then
          sc=$(shellcheck -f gcc "${f}" 2>&1)
        elif [ "${d}" = bash ]; then
          sc=$(shellcheck -f gcc -s bash "${f}" 2>&1)
        else
          sc=$(shellcheck -f gcc -s sh "${f}" 2>&1)
        fi
        printf '%s\n' "${sc}" | awk '
          match($0, /:[0-9]+:[0-9]+: (error|warning|note): /) {
            file = substr($0, 1, RSTART - 1)
            hdr = substr($0, RSTART, RLENGTH)
            rest = substr($0, RSTART + RLENGTH)
            split(hdr, a, ":")
            ln = a[2]
            lv = a[4]
            gsub(/ /, "", lv)
            lv = (lv == "error") ? "ERROR" : "WARN"
            code = "SC"
            if (match(rest, / \[SC[0-9]+\]$/)) {
              code = substr(rest, RSTART + 2, RLENGTH - 3)
              rest = substr(rest, 1, RSTART - 1)
            }
            printf "%s %s:%s [%s] %s\n", lv, file, ln, code, rest
          }' >> "${out}"
      else
        skip_once shellcheck "not installed; heuristics only (see platform-detection for hints)"
      fi
      if [ "${d}" = bash ]; then
        if have bash; then
          se=$(bash -n "${f}" 2>&1 | head -n 1)
        else
          se=""
          skip_once bash-syntax "bash not installed"
        fi
      elif [ -n "${posix_sh}" ]; then
        se=$(posix_syntax "${f}" | head -n 1)
      else
        se=""
        skip_once posix-syntax "no POSIX shell available"
      fi
      [ -n "${se}" ] && echo "ERROR ${f}:1 [SYN] ${se}" | cut -c1-200 >> "${out}"
      if have shfmt; then
        if has_editorconfig "${f}"; then
          fd=$(shfmt -d "${f}" 2>&1)
          fr=$?
          if [ "${fr}" -ne 0 ]; then
            case ${fd} in
              ---* | diff*)
                hunks=$(printf '%s\n' "${fd}" | grep -c '^@@')
                echo "WARN ${f}:1 [FMT] shfmt: ${hunks} hunk(s) differ from .editorconfig style (fix: shfmt -w ${f})" >> "${out}"
                ;;
              *) echo "WARN ${f}:1 [FMT] shfmt could not parse: $(printf '%s' "${fd}" | head -n 1)" | cut -c1-200 >> "${out}" ;;
            esac
          fi
        else
          skip_once shfmt "no .editorconfig found; formatting style unverifiable"
        fi
      else
        skip_once shfmt "not installed; formatting unverified (see platform-detection)"
      fi
      ;;
    zsh)
      if have zsh; then
        se=$(zsh -n "${f}" 2>&1 | head -n 1)
        [ -n "${se}" ] && echo "ERROR ${f}:1 [SYN] ${se}" | cut -c1-200 >> "${out}"
      else
        skip_once zsh-syntax "zsh not installed (WSL or MSYS2 provide it); zsh files checked by heuristics only"
      fi
      case ${f##*/} in
        *.zsh)
          if have shfmt && has_editorconfig "${f}"; then
            # shfmt parses .zsh as bash unless it is a release with zsh support
            if [ -z "${shfmt_zsh:-}" ]; then
              if printf 'echo hi\n' | shfmt -ln zsh > /dev/null 2>&1; then shfmt_zsh=yes; else shfmt_zsh=no; fi
            fi
            if [ "${shfmt_zsh}" = yes ]; then
              hunks=$(shfmt -d "${f}" 2>&1 | grep -c '^@@' || true)
              [ "${hunks:-0}" -gt 0 ] && echo "INFO ${f}:1 [FMT] shfmt advisory (zsh): ${hunks} hunk(s) differ from .editorconfig; review with shfmt -d, never write" >> "${out}"
            else
              skip_once shfmt-zsh "installed shfmt has no zsh support; zsh formatting not checked"
            fi
          fi
          ;;
      esac
      ;;
  esac
}

# Build the file list.
: > "${tmp}/files.list"
if [ -s "${tmp}/args.list" ]; then
  while IFS= read -r a; do
    if [ -d "${a}" ]; then
      find "${a}" -type f ! -path '*/.git/*' | LC_ALL=C sort >> "${tmp}/files.list"
    elif [ -f "${a}" ]; then
      printf '%s\n' "${a}" >> "${tmp}/files.list"
    else
      echo "lint-shell: not found: ${a}" >&2
      exit 2
    fi
  done < "${tmp}/args.list"
else
  if [ -z "${root}" ]; then
    root=$(git rev-parse --show-toplevel 2> /dev/null || pwd)
  fi
  cd "${root}" 2> /dev/null || {
    echo "lint-shell: cannot enter root: ${root}" >&2
    exit 2
  }
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -c core.quotepath=off ls-files -co --exclude-standard | awk '!/^\.agents?\// && !/^\.artifacts\//' > "${tmp}/files.list"
  else
    find . -type f ! -path './.git/*' ! -path './.agent/*' ! -path './.agents/*' ! -path './.artifacts/*' | sed 's|^\./||' | LC_ALL=C sort > "${tmp}/files.list"
  fi
fi

nfiles=0
while IFS= read -r f; do
  [ -f "${f}" ] || continue
  if [ -n "${dialect_force}" ]; then
    d=${dialect_force}
  else
    d=$(detect_dialect "${f}")
  fi
  [ "${d}" = "other" ] && continue
  if [ "${list_only}" -eq 1 ]; then
    printf '%s\t%s\n' "${d}" "${f}"
    continue
  fi
  nfiles=$((nfiles + 1))
  lint_file "${f}" "${d}"
done < "${tmp}/files.list"
[ "${list_only}" -eq 1 ] && exit 0

if [ "${external}" -eq 0 ]; then
  skipped="${skipped} external-tools(requested)"
fi
if [ "${nfiles}" -eq 0 ]; then
  echo "NOTE no shell-like files found"
fi
errors=$(grep -c '^ERROR ' "${out}" || true)
warns=$(grep -c '^WARN ' "${out}" || true)
infos=$(grep -c '^INFO ' "${out}" || true)
if [ -n "${skipped# }" ]; then
  cov=partial
else
  cov=full
fi
summary="SUMMARY files=${nfiles} errors=${errors} warnings=${warns} info=${infos} coverage=${cov} skipped=$(echo "${skipped# }" | tr ' ' ',')"
if [ -n "${outfile}" ]; then
  mkdir -p "$(dirname "${outfile}")" || exit 2
  {
    cat "${out}"
    echo "${summary}"
  } > "${outfile}" || exit 2
  case ${outfile} in
    */.artifacts/*) [ -e "${outfile%%/.artifacts/*}/.artifacts/.gitignore" ] || printf '*\n' > "${outfile%%/.artifacts/*}/.artifacts/.gitignore" ;;
  esac
  echo "lint-shell: findings written to ${outfile}"
else
  cat "${out}"
fi
echo "${summary}"
[ "${errors}" -gt 0 ] && exit 1
[ "${strict}" -eq 1 ] && [ "${warns}" -gt 0 ] && exit 1
exit 0
