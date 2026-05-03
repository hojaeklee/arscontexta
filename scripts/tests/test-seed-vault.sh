#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SEED="$PROJECT_ROOT/scripts/seed-vault.sh"

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
    fail "did not expect output to contain: $needle"
  fi
}

assert_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >"$tmp_dir/out" 2>&1
  local actual=$?
  output="$(cat "$tmp_dir/out")"
  set -e
  [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected but got $actual from $*; output: $output"
  printf '%s' "$output"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-seed-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_vault="$tmp_dir/missing-vault"
mkdir -p "$missing_vault"
missing_output="$(assert_exit 1 "$SEED" "$missing_vault" --file missing.md)"
assert_contains "$missing_output" "ERROR: Source file not found"

external_vault="$tmp_dir/external-vault"
mkdir -p "$external_vault/ops/queue/archive" "$external_vault/notes" "$external_vault/inbox"
cat > "$external_vault/living doc.md" <<'EOF'
# Living Doc

Useful durable source.
EOF
mkdir -p "$external_vault/ops/queue/archive/old"
touch "$external_vault/ops/queue/archive/old/older-009.md"
external_output="$("$SEED" "$external_vault" --file "living doc.md" --scope "Architecture notes")"
assert_contains "$external_output" "Seeded: living-doc"
assert_contains "$external_output" "Source moved: no"
assert_contains "$external_output" "Task file: ops/queue/living-doc.md"
assert_contains "$external_output" "Claims will start at: 10"
[[ -f "$external_vault/living doc.md" ]] || fail "source outside inbox should remain in place"
[[ -f "$external_vault/ops/queue/living-doc.md" ]] || fail "task file should be created"
assert_contains "$(cat "$external_vault/ops/queue/living-doc.md")" "Scope"
assert_contains "$(cat "$external_vault/ops/queue/living-doc.md")" "Architecture notes"
assert_contains "$(cat "$external_vault/ops/queue/queue.yaml")" "id: living-doc"

inbox_vault="$tmp_dir/inbox-vault"
mkdir -p "$inbox_vault/ops/queue/archive" "$inbox_vault/inbox" "$inbox_vault/notes"
cat > "$inbox_vault/ops/queue/queue.json" <<'EOF'
{
  "tasks": [
    {
      "id": "existing",
      "type": "extract",
      "status": "pending",
      "source": "ops/queue/archive/old/existing.md",
      "file": "existing.md",
      "next_claim_start": 12
    }
  ]
}
EOF
cat > "$inbox_vault/inbox/Research Source.md" <<'EOF'
# Research Source

Line one.
Line two.
EOF
inbox_output="$("$SEED" "$inbox_vault" --file "Research Source.md" --format json)"
assert_contains "$inbox_output" '"id": "research-source"'
assert_contains "$inbox_output" '"source_moved": true'
assert_contains "$inbox_output" '"queue_file": "ops/queue/queue.json"'
assert_contains "$inbox_output" '"next_claim_start": 13'
[[ ! -f "$inbox_vault/inbox/Research Source.md" ]] || fail "inbox source should be moved"
find "$inbox_vault/ops/queue/archive" -path '*-research-source/Research Source.md' -type f | grep -Fq "Research Source.md" || fail "moved source should be in archive"
assert_contains "$(cat "$inbox_vault/ops/queue/queue.json")" '"id": "research-source"'
assert_contains "$(cat "$inbox_vault/ops/queue/research-source.md")" "Archived:"

duplicate_before="$(cat "$inbox_vault/ops/queue/queue.json")"
duplicate_output="$("$SEED" "$inbox_vault" --file "$inbox_vault/ops/queue/archive/"*"-research-source/Research Source.md")"
assert_contains "$duplicate_output" "Duplicate source detected"
assert_contains "$duplicate_output" "No queue changes made"
duplicate_after="$(cat "$inbox_vault/ops/queue/queue.json")"
[[ "$duplicate_before" == "$duplicate_after" ]] || fail "duplicate detection should not mutate queue"

collision_vault="$tmp_dir/collision-vault"
mkdir -p "$collision_vault/inbox" "$collision_vault/ops/queue/archive"
cat > "$collision_vault/inbox/Collision.md" <<'EOF'
# Collision
EOF
today="$(date -u +%Y-%m-%d)"
mkdir -p "$collision_vault/ops/queue/archive/$today-collision"
collision_output="$("$SEED" "$collision_vault" --file inbox/Collision.md)"
assert_contains "$collision_output" "Archive folder: ops/queue/archive/$today-collision-2"
[[ -d "$collision_vault/ops/queue/archive/$today-collision" ]] || fail "existing archive folder should remain"
[[ -d "$collision_vault/ops/queue/archive/$today-collision-2" ]] || fail "new archive folder should avoid collision"

url_output="$(assert_exit 2 "$SEED" "$collision_vault" --file "https://example.com/article")"
assert_contains "$url_output" "requires a file path"

printf 'PASS: seed-vault checks\n'
