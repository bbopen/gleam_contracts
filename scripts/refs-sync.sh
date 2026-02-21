#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
refs_dir="$ROOT_DIR/_refs"
refs_file="$refs_dir/refs.toml"
lock_file="$refs_dir/refs.lock.toml"

say() { printf '%s\n' "$*" >&2; }
fail() { say "FAIL: $*"; exit 1; }

[[ -d "$refs_dir" ]] || fail "missing _refs/ directory"
[[ -f "$refs_file" ]] || fail "missing _refs/refs.toml"

pick_input_file() {
  if [[ -f "$lock_file" ]]; then
    # Use the lock file if it contains at least one [[ref]] entry.
    if python3 - "$lock_file" <<'PY'
import sys, tomllib, pathlib
p = pathlib.Path(sys.argv[1])
data = tomllib.loads(p.read_text(encoding="utf-8"))
refs = data.get("ref", [])
sys.exit(0 if refs else 1)
PY
    then
      echo "$lock_file"
      return
    fi
  fi

  echo "$refs_file"
}

input_file="$(pick_input_file)"
say "Using refs input: $input_file"

refs_tsv="$(
  python3 - "$input_file" <<'PY'
import sys, tomllib, pathlib
p = pathlib.Path(sys.argv[1])
data = tomllib.loads(p.read_text(encoding="utf-8"))
refs = data.get("ref", [])
for r in refs:
  name = r.get("name", "").strip()
  url = r.get("url", "").strip()
  tag = (r.get("tag") or "").strip()
  rev = (r.get("rev") or "").strip()
  if not name or not url:
    raise SystemExit("Each [[ref]] must include name and url")
  print("\t".join([name, url, tag, rev]))
PY
)"

if [[ -z "$refs_tsv" ]]; then
  say "No refs configured; nothing to do."
  exit 0
fi

tmp_lock="$(mktemp)"
cat > "$tmp_lock" <<'EOF'
# Pinned revisions for `_refs/refs.toml`.
#
# This file is tracked so reference checkouts are reproducible across machines.

EOF

while IFS=$'\t' read -r name url tag rev; do
  dest="$refs_dir/$name"

  say ""
  say "== $name =="
  say "url: $url"
  if [[ -n "$tag" ]]; then say "tag: $tag"; fi
  if [[ -n "$rev" ]]; then say "rev: $rev"; fi

  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" remote set-url origin "$url"
    git -C "$dest" fetch --tags origin
  elif [[ -e "$dest" ]]; then
    fail "ref path exists but is not a git repo: $dest"
  else
    git clone "$url" "$dest"
  fi

  if [[ -n "$rev" ]]; then
    git -C "$dest" checkout --quiet "$rev"
  elif [[ -n "$tag" ]]; then
    git -C "$dest" checkout --quiet "$tag"
  else
    # Default: stay on the repo default branch HEAD
    git -C "$dest" checkout --quiet "$(git -C "$dest" symbolic-ref --short HEAD)"
  fi

  pinned="$(git -C "$dest" rev-parse HEAD)"
  say "pinned: $pinned"

  cat >> "$tmp_lock" <<EOF
[[ref]]
name = "$name"
url = "$url"
rev = "$pinned"

EOF
done <<< "$refs_tsv"

mv "$tmp_lock" "$lock_file"
say ""
say "OK: wrote $lock_file"
