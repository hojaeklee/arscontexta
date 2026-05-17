#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
GENERATOR="$PROJECT_ROOT/scripts/fixtures/generate-large-vault.py"
INDEX="$PROJECT_ROOT/plugins/hippocampusmd/scripts/vault-index.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  grep -Fq -- "$needle" <<<"$haystack" || fail "expected output to contain: $needle"
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-large-fixture-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/large-vault"
"$GENERATOR" "$vault" \
  --notes 1000 \
  --aliases-per-note 3 \
  --duplicate-basenames 4 \
  --dense-moc-links 120 \
  --high-link-count 80 \
  --imported-files 6 \
  --archive-files 5 \
  --attachment-files 4

assert_file "$vault/ops/config.yaml"
assert_file "$vault/ops/cache/performance-budgets.json"
assert_file "$vault/notes/maps/index.md"
assert_file "$vault/notes/high-link-hub.md"
assert_file "$vault/notes/dupes/group-00/duplicate.md"
assert_file "$vault/notes/dupes/group-03/duplicate.md"
assert_file "$vault/imported/source-000.md"
assert_file "$vault/archive/old-000.md"
assert_file "$vault/attachments/file-000.md"

first_output="$("$INDEX" build "$vault")"
assert_contains "$first_output" "scanned: 1000"
assert_contains "$first_output" "skipped: 0"
assert_contains "$first_output" "ignored: 15"

second_output="$("$INDEX" build "$vault")"
assert_contains "$second_output" "scanned: 0"
assert_contains "$second_output" "skipped: 1000"
assert_contains "$second_output" "ignored: 15"

status_json="$("$INDEX" status "$vault" --format json)"
assert_contains "$status_json" '"indexed_notes": 1000'
assert_contains "$status_json" '"ignored_files": 15'
assert_contains "$status_json" '"ignored_exclude_match": 15'
assert_contains "$status_json" '"duplicate_basenames": 1'

export_json="$("$INDEX" export "$vault" --format json)"
assert_contains "$export_json" '"path": "notes/maps/index.md"'
assert_contains "$export_json" '"path": "notes/high-link-hub.md"'
assert_contains "$export_json" '"path": "notes/dupes/group-00/duplicate.md"'
assert_contains "$export_json" '"path": "notes/dupes/group-03/duplicate.md"'
assert_contains "$export_json" '"alias-0000-00"'
assert_contains "$export_json" '"target": "Note 0000"'
assert_contains "$export_json" '"target": "Duplicate 0"'

budget_json="$(cat "$vault/ops/cache/performance-budgets.json")"
assert_contains "$budget_json" '"fixture_notes": 1000'
assert_contains "$budget_json" '"index_rescan_expected_scanned": 0'
assert_contains "$budget_json" '"index_rescan_expected_skipped": 1000'
assert_contains "$budget_json" '"graph_neighborhood_seconds"'

printf 'PASS: large-vault fixture checks\n'
