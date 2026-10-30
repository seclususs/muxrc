#!/bin/sh
# format-shell.sh - shfmt wrapper that follows the project's .editorconfig.
# Check mode by default (prints a diff, changes nothing); --write rewrites sh and
# bash files. zsh files are never rewritten. File discovery is lint-shell.sh --list.

set -u

here=$(cd "$(dirname "$0")" && pwd)
lint="${here}/lint-shell.sh"

usage() {
  cat << 'EOF'
Usage: format-shell.sh [options] [PATH ...]

Format sh/bash files with shfmt using the project's .editorconfig. No style flags
are passed on purpose: any shfmt parser or printer flag makes shfmt ignore
.editorconfig. A file without an .editorconfig in its directory chain is skipped,
because shfmt would apply its own defaults (tabs). zsh files are skipped:
shfmt can corrupt zsh syntax, so review them with shfmt -d by hand.
No PATH: every shell-like file of the repository (agent dirs excluded).

Options:
  --write         rewrite sh and bash files in place (default: print the diff only)
  --root DIR      project root (default: git toplevel, else current dir)
  --out FILE      write the diff to FILE (UTF-8, LF); convention:
                  .artifacts/format/diff.txt at the project root
  -h, --help      show this help

Output: diff (check mode), SKIP lines, then one line:
  SUMMARY files=N differing=N written=N skipped=N shfmt=VERSION
Exit: 0 nothing differs (or --write succeeded), 1 files differ in check mode
or shfmt reported an error, 2 usage error, 3 shfmt not installed.
EOF
}

write=0
root=""
outfile=""
args=""
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --write)
      write=1
      shift
      ;;
    --root | --out)
      [ $# -ge 2 ] || {
        echo "format-shell: $1 needs a value" >&2
        exit 2
      }
      if [ "$1" = --root ]; then
        root=$2
      else
        outfile=$2
        case ${outfile} in /*) ;; *) outfile="$(pwd)/${outfile}" ;; esac
      fi
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "format-shell: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      args="${args}
$1"
      shift
      ;;
  esac
done
while [ $# -gt 0 ]; do
  args="${args}
$1"
  shift
done

if ! command -v shfmt > /dev/null 2>&1; then
  echo "format-shell: shfmt not installed; formatting not checked." >&2
  echo "format-shell: install it (see platform-detection for the host package manager) or format by hand following .editorconfig." >&2
  exit 3
fi
[ -f "${lint}" ] || {
  echo "format-shell: lint-shell.sh not found next to this script" >&2
  exit 2
}

tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/format-shell.$$")
mkdir -p "${tmp}"
trap 'rm -rf "${tmp}"' EXIT INT TERM

# File discovery and dialect detection are shared with the linter
printf '%s\n' "${args}" | while IFS= read -r a; do
  [ -n "${a}" ] && printf '%s\n' "${a}" >> "${tmp}/lint.paths"
done
set -- --list
[ -n "${root}" ] && set -- "$@" --root "${root}"
if [ -s "${tmp}/lint.paths" ]; then
  while IFS= read -r a; do set -- "$@" "${a}"; done < "${tmp}/lint.paths"
fi
sh "${lint}" "$@" > "${tmp}/files.tsv" || exit 2
# lint-shell enters the project root when it discovers files itself
if [ -z "${root}" ] && [ ! -s "${tmp}/lint.paths" ]; then
  root=$(git rev-parse --show-toplevel 2> /dev/null || pwd)
fi
if [ -n "${root}" ] && [ ! -s "${tmp}/lint.paths" ]; then
  cd "${root}" 2> /dev/null || {
    echo "format-shell: cannot enter root: ${root}" >&2
    exit 2
  }
fi

has_editorconfig() {
  d=$(cd "$(dirname "$1")" && pwd)
  while :; do
    [ -f "${d}/.editorconfig" ] && return 0
    [ "${d}" = "/" ] && return 1
    d=$(dirname "${d}")
  done
}

total=0
differing=0
written=0
skipped=0
failed=0
: > "${tmp}/report"
tab=$(printf '\t')
while IFS="${tab}" read -r dialect f; do
  [ -n "${f}" ] || continue
  total=$((total + 1))
  case ${dialect} in
    zsh)
      echo "SKIP ${f}: zsh is never rewritten; review with shfmt -d by hand" >> "${tmp}/report"
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  if ! has_editorconfig "${f}"; then
    echo "SKIP ${f}: no .editorconfig; shfmt defaults would restyle the file" >> "${tmp}/report"
    skipped=$((skipped + 1))
    continue
  fi
  if d=$(shfmt -d "${f}" 2>&1); then
    continue
  fi
  case ${d} in
    *'@@'*) ;;
    *)
      echo "ERROR ${f}: shfmt could not parse: $(printf '%s' "${d}" | head -n 1)" >> "${tmp}/report"
      failed=$((failed + 1))
      continue
      ;;
  esac
  differing=$((differing + 1))
  if [ "${write}" -eq 1 ]; then
    if shfmt -w "${f}" 2> /dev/null; then
      written=$((written + 1))
      echo "WROTE ${f}" >> "${tmp}/report"
    else
      echo "ERROR ${f}: shfmt could not write" >> "${tmp}/report"
      failed=$((failed + 1))
    fi
  else
    printf '%s\n' "${d}" >> "${tmp}/diff"
  fi
done < "${tmp}/files.tsv"

version=$(shfmt --version 2> /dev/null | head -n 1)
summary="SUMMARY files=${total} differing=${differing} written=${written} skipped=${skipped} shfmt=${version:-unknown}"
if [ -n "${outfile}" ]; then
  mkdir -p "$(dirname "${outfile}")" || exit 2
  {
    cat "${tmp}/diff" 2> /dev/null
    cat "${tmp}/report"
    echo "${summary}"
  } > "${outfile}" || exit 2
  case ${outfile} in
    */.artifacts/*) [ -e "${outfile%%/.artifacts/*}/.artifacts/.gitignore" ] || printf '*\n' > "${outfile%%/.artifacts/*}/.artifacts/.gitignore" ;;
  esac
  echo "format-shell: output written to ${outfile}"
else
  cat "${tmp}/diff" 2> /dev/null
  cat "${tmp}/report"
fi
echo "${summary}"
[ "${failed}" -gt 0 ] && exit 1
[ "${write}" -eq 0 ] && [ "${differing}" -gt 0 ] && exit 1
exit 0
