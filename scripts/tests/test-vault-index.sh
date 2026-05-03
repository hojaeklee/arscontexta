#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
INDEX="$PROJECT_ROOT/plugins/arscontexta/scripts/vault-index.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "expected output not to contain: $needle"
  fi
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-vault-index-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes/a" "$vault/notes/b" "$vault/ops"

cat > "$vault/notes/a/duplicate.md" <<'EOF'
---
description: First duplicate basename claim
type: claim
aliases:
  - first duplicate
topics: ["[[index]]"]
created: 2026-05-03
---

# First Duplicate

Links to [[Second Duplicate]] and [[missing target]].
EOF

cat > "$vault/notes/b/duplicate.md" <<'EOF'
---
description: Second duplicate basename topic map
type: moc
aliases: ["Second Duplicate"]
topics: ["[[index]]"]
created: 2026-05-03
---

# Second Duplicate

Links to [[First Duplicate]].
EOF

cat > "$vault/notes/bad.md" <<'EOF'
---
description: Broken frontmatter never closes
type: claim

# Bad

This file should produce a parse warning without aborting the scan.
EOF

first_output="$("$INDEX" build "$vault")"
assert_contains "$first_output" "scanned: 3"
assert_contains "$first_output" "skipped: 0"
assert_contains "$first_output" "deleted: 0"
assert_contains "$first_output" "warnings: 1"
assert_file "$vault/ops/cache/index.sqlite"

second_output="$("$INDEX" build "$vault")"
assert_contains "$second_output" "scanned: 0"
assert_contains "$second_output" "skipped: 3"
assert_contains "$second_output" "deleted: 0"

status_json="$("$INDEX" status "$vault" --format json)"
assert_contains "$status_json" '"indexed_notes": 3'
assert_contains "$status_json" '"warnings": 1'
assert_contains "$status_json" '"duplicate_basenames": 1'

export_json="$("$INDEX" export "$vault" --format json)"
assert_contains "$export_json" '"path": "notes/a/duplicate.md"'
assert_contains "$export_json" '"path": "notes/b/duplicate.md"'
assert_contains "$export_json" '"basename": "duplicate"'
assert_contains "$export_json" '"target": "Second Duplicate"'
assert_contains "$export_json" '"message": "Unterminated frontmatter block."'

rm "$vault/notes/a/duplicate.md"
delete_output="$("$INDEX" build "$vault")"
assert_contains "$delete_output" "deleted: 1"

after_delete_json="$("$INDEX" export "$vault" --format json)"
assert_not_contains "$after_delete_json" '"path": "notes/a/duplicate.md"'
assert_contains "$after_delete_json" '"path": "notes/b/duplicate.md"'

printf 'PASS: vault-index checks\n'
