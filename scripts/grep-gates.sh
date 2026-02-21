#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="cross"

say() { printf '%s\n' "$*" >&2; }
fail() { say "FAIL: $*"; exit 1; }

have_rg() { command -v rg >/dev/null 2>&1; }

search_has_match_fixed() {
  local pattern="$1"
  shift

  if have_rg; then
    rg -n -F --glob '*.gleam' -- "$pattern" "$@" >/dev/null 2>&1
  else
    grep -RIn -F --include='*.gleam' -- "$pattern" "$@" >/dev/null 2>&1
  fi
}

search_print_matches_fixed() {
  local pattern="$1"
  shift

  if have_rg; then
    rg -n -F --glob '*.gleam' -- "$pattern" "$@" || true
  else
    grep -RIn -F --include='*.gleam' -- "$pattern" "$@" || true
  fi
}

search_has_match_regex() {
  local pattern="$1"
  shift

  if have_rg; then
    rg -n --glob '*.gleam' -- "$pattern" "$@" >/dev/null 2>&1
  else
    grep -RIn -E --include='*.gleam' -- "$pattern" "$@" >/dev/null 2>&1
  fi
}

search_print_matches_regex() {
  local pattern="$1"
  shift

  if have_rg; then
    rg -n --glob '*.gleam' -- "$pattern" "$@" || true
  else
    grep -RIn -E --include='*.gleam' -- "$pattern" "$@" || true
  fi
}

list_files_with_match() {
  local pattern="$1"
  shift

  if have_rg; then
    rg -l -F --glob '*.gleam' -- "$pattern" "$@" 2>/dev/null || true
  else
    grep -RIl -F --include='*.gleam' -- "$pattern" "$@" 2>/dev/null || true
  fi
}

check_no_match() {
  local description="$1"
  local pattern="$2" # fixed string
  shift 2

  if search_has_match_fixed "$pattern" "$@"; then
    say ""
    say "Found forbidden pattern: $description"
    search_print_matches_fixed "$pattern" "$@"
    fail "$description"
  fi
}

check_no_match_regex() {
  local description="$1"
  local pattern="$2" # regex
  shift 2

  if search_has_match_regex "$pattern" "$@"; then
    say ""
    say "Found forbidden pattern: $description"
    search_print_matches_regex "$pattern" "$@"
    fail "$description"
  fi
}

check_toml_no_target() {
  local toml="$ROOT_DIR/gleam.toml"
  [[ -f "$toml" ]] || return 0

  if command -v rg >/dev/null 2>&1; then
    if rg -n '^target\\s*=' "$toml" >/dev/null 2>&1; then
      rg -n '^target\\s*=' "$toml" || true
      fail "cross-target libs must not set target in gleam.toml"
    fi
  else
    if grep -nE '^target[[:space:]]*=' "$toml" >/dev/null 2>&1; then
      grep -nE '^target[[:space:]]*=' "$toml" || true
      fail "cross-target libs must not set target in gleam.toml"
    fi
  fi
}

src_dir="$ROOT_DIR/src"
test_dir="$ROOT_DIR/test"

[[ -d "$src_dir" ]] || fail "missing src/ directory"

search_dirs=("$src_dir")
if [[ -d "$test_dir" ]]; then
  search_dirs+=("$test_dir")
fi

check_no_match_regex "todo keyword in src/ (ship no todo)" '(^|[^[:alnum:]_])todo([^[:alnum:]_]|$)' "$src_dir"
check_no_match_regex "panic keyword in src/ (ship no panic)" '(^|[^[:alnum:]_])panic([^[:alnum:]_]|$)' "$src_dir"

check_no_match "dynamic.unsafe_coerce (breaks type safety)" "dynamic.unsafe_coerce" "${search_dirs[@]}"
check_no_match "@deprecated (avoid in initial releases)" "@deprecated" "$src_dir"

external_files="$(list_files_with_match "@external" "${search_dirs[@]}")"

if [[ "$TARGET" == "cross" ]]; then
  if [[ -n "$external_files" ]]; then
    say ""
    say "Cross-target libs must not use @external. Found in:"
    say "$external_files"
    fail "@external is forbidden in cross-target libs"
  fi

  check_no_match "import gleam/erlang (cross-target forbidden)" "import gleam/erlang" "${search_dirs[@]}"
  check_no_match "import gleam/javascript (cross-target forbidden)" "import gleam/javascript" "${search_dirs[@]}"
  check_toml_no_target
else
  # Erlang-target libs may use FFI, but it must be isolated to clearly-named modules.
  if [[ -n "$external_files" ]]; then
    bad_files=""
    while IFS= read -r f; do
      case "$f" in
        */ffi.gleam|*/ffi_*.gleam|*/*_ffi.gleam|*/ffi/*.gleam) ;;
        *) bad_files="${bad_files}${bad_files:+$'\n'}${f}" ;;
      esac
    done <<< "$external_files"

    if [[ -n "$bad_files" ]]; then
      say ""
      say "@external must be isolated to FFI modules:"
      say "  allowed: src/**/ffi.gleam, src/**/ffi_*.gleam, src/**/*_ffi.gleam, src/**/ffi/*.gleam"
      say "Move FFI declarations into a dedicated module and wrap them with typed functions."
      say ""
      say "Disallowed @external usage found in:"
      say "$bad_files"
      fail "@external isolation gate failed"
    fi
  fi
fi

check_module_doc() {
  local f="$1"
  local first

  first="$(awk '
    /^[[:space:]]*$/ { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      print NR ":" line
      exit
    }
  ' "$f")"

  if [[ -z "$first" ]]; then
    fail "empty Gleam source file: $f"
  fi

  if [[ "${first#*:}" != "////"* ]]; then
    say ""
    say "Missing module doc comment (////) at top of file:"
    say "  $f"
    say "  first non-empty line: $first"
    fail "module doc gate failed"
  fi
}

check_pub_docs() {
  local f="$1"

  if ! awk -v file="$f" '
    function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
    function is_attr(s) { return s ~ /^@/ }
    function is_pub_def(s) { return s ~ /^pub[[:space:]]+(fn|type|const|opaque[[:space:]]+type)/ }

    /^[[:space:]]*$/ { buf_len = 0; next }
    {
      line = ltrim($0)

      if (is_pub_def(line)) {
        j = buf_len
        while (j >= 1 && is_attr(buf[j])) { j-- }
        if (j < 1 || buf[j] !~ /^\/\/\/($|[[:space:]])/) {
          printf("%s:%d: public item missing /// doc comment\n", file, NR) > "/dev/stderr"
          exit 1
        }
      }

      buf_len++
      buf[buf_len] = line
    }
  ' "$f"; then
    fail "public doc gate failed"
  fi
}

while IFS= read -r -d '' f; do
  check_module_doc "$f"
  check_pub_docs "$f"
done < <(find "$src_dir" -type f -name '*.gleam' -print0)

say "OK: grep gates passed"
