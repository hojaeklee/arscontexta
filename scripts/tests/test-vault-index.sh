#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
INDEX="${ARS_CONTEXTA_INDEX:-$PROJECT_ROOT/plugins/arscontexta/scripts/vault-index.sh}"

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
mkdir -p \
  "$vault/notes/a" \
  "$vault/notes/b" \
  "$vault/archive" \
  "$vault/imported" \
  "$vault/attachments" \
  "$vault/ops/cache" \
  "$vault/ops/health" \
  "$vault/ops/sessions"

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

Links to [[Second Duplicate]], [[missing target]], and [[missing target]] again.
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

for ignored_rel in \
  archive/old.md \
  imported/source.md \
  attachments/file.md \
  ops/cache/generated.md \
  ops/health/report.md \
  ops/sessions/session.md
do
  printf '# Ignored\n\nThis file should not be indexed.\n' > "$vault/$ignored_rel"
done

first_output="$("$INDEX" build "$vault")"
assert_contains "$first_output" "scanned: 3"
assert_contains "$first_output" "skipped: 0"
assert_contains "$first_output" "deleted: 0"
assert_contains "$first_output" "ignored: 6"
assert_contains "$first_output" "warnings: 1"
assert_file "$vault/ops/cache/index.sqlite"

second_output="$("$INDEX" build "$vault")"
assert_contains "$second_output" "scanned: 0"
assert_contains "$second_output" "skipped: 3"
assert_contains "$second_output" "deleted: 0"
assert_contains "$second_output" "ignored: 6"

status_json="$("$INDEX" status "$vault" --format json)"
assert_contains "$status_json" '"indexed_notes": 3'
assert_contains "$status_json" '"ignored_files": 6'
assert_contains "$status_json" '"ignored_include_miss": 0'
assert_contains "$status_json" '"ignored_exclude_match": 6'
assert_contains "$status_json" '"links": 6'
assert_contains "$status_json" '"warnings": 1'
assert_contains "$status_json" '"duplicate_basenames": 1'

export_json="$("$INDEX" export "$vault" --format json)"
assert_contains "$export_json" '"path": "notes/a/duplicate.md"'
assert_contains "$export_json" '"path": "notes/b/duplicate.md"'
assert_contains "$export_json" '"basename": "duplicate"'
assert_contains "$export_json" '"ordinal": 3'
assert_contains "$export_json" '"target": "Second Duplicate"'
assert_contains "$export_json" '"message": "Unterminated frontmatter block."'

rm "$vault/notes/a/duplicate.md"
delete_output="$("$INDEX" build "$vault")"
assert_contains "$delete_output" "deleted: 1"

after_delete_json="$("$INDEX" export "$vault" --format json)"
assert_not_contains "$after_delete_json" '"path": "notes/a/duplicate.md"'
assert_contains "$after_delete_json" '"path": "notes/b/duplicate.md"'

include_vault="$tmp_dir/include-vault"
mkdir -p "$include_vault/research" "$include_vault/notes"
cat > "$include_vault/ops-config-placeholder" <<'EOF'
placeholder
EOF
mkdir -p "$include_vault/ops"
cat > "$include_vault/ops/config.yaml" <<'EOF'
scan:
  include:
    - research/**
  exclude: []
EOF
printf '# Included\n' > "$include_vault/research/keep.md"
printf '# Include miss\n' > "$include_vault/notes/skip.md"

include_output="$("$INDEX" build "$include_vault")"
assert_contains "$include_output" "scanned: 1"
assert_contains "$include_output" "ignored: 1"
include_json="$("$INDEX" status "$include_vault" --format json)"
assert_contains "$include_json" '"indexed_notes": 1'
assert_contains "$include_json" '"ignored_include_miss": 1'
assert_contains "$include_json" '"ignored_exclude_match": 0'
include_export="$("$INDEX" export "$include_vault" --format json)"
assert_contains "$include_export" '"path": "research/keep.md"'
assert_not_contains "$include_export" '"path": "notes/skip.md"'

override_vault="$tmp_dir/override-vault"
mkdir -p "$override_vault/notes/private" "$override_vault/ops"
cat > "$override_vault/ops/config.yaml" <<'EOF'
scan:
  include:
    - notes/**
  exclude:
    - notes/private/**
EOF
printf '# Public\n' > "$override_vault/notes/public.md"
printf '# Private\n' > "$override_vault/notes/private/secret.md"

override_output="$("$INDEX" build "$override_vault")"
assert_contains "$override_output" "scanned: 1"
assert_contains "$override_output" "ignored: 1"
override_json="$("$INDEX" status "$override_vault" --format json)"
assert_contains "$override_json" '"ignored_include_miss": 0'
assert_contains "$override_json" '"ignored_exclude_match": 1'
override_export="$("$INDEX" export "$override_vault" --format json)"
assert_contains "$override_export" '"path": "notes/public.md"'
assert_not_contains "$override_export" '"path": "notes/private/secret.md"'

migrate_vault="$tmp_dir/migrate-vault"
mkdir -p "$migrate_vault/notes" "$migrate_vault/ops/cache"
cat > "$migrate_vault/notes/alpha.md" <<'EOF'
---
description: Alpha claim
type: claim
---

# Alpha

Links to [[Beta]] and [[Gamma]].
EOF

cat > "$migrate_vault/notes/beta.md" <<'EOF'
---
description: Beta claim
type: claim
---

# Beta

Links back to [[Alpha]].
EOF

migrate_initial="$("$INDEX" build "$migrate_vault")"
assert_contains "$migrate_initial" "scanned: 2"
assert_contains "$migrate_initial" "skipped: 0"

sqlite3 "$migrate_vault/ops/cache/index.sqlite" <<'SQL'
DROP TABLE links;
CREATE TABLE links (
  source_path TEXT NOT NULL,
  target TEXT NOT NULL,
  raw TEXT NOT NULL,
  PRIMARY KEY (source_path, target, raw),
  FOREIGN KEY (source_path) REFERENCES notes(path) ON DELETE CASCADE
);
INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', '1');
SQL

migrate_rebuild="$("$INDEX" build "$migrate_vault")"
assert_contains "$migrate_rebuild" "scanned: 2"
assert_contains "$migrate_rebuild" "skipped: 0"
migrate_status="$("$INDEX" status "$migrate_vault" --format json)"
assert_contains "$migrate_status" '"indexed_notes": 2'
assert_contains "$migrate_status" '"links": 3'

printf 'PASS: vault-index checks\n'
