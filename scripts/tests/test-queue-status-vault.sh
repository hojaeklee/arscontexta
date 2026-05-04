#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATUS="$PROJECT_ROOT/plugins/hippocampusmd/scripts/queue-status-vault.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}
assert_not_exists() { [[ ! -e "$1" ]] || fail "expected file not to exist: $1"; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-queue-status-test.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/ops/queue/archive" "$vault/ops/tasks.md.d"
cat > "$vault/ops/queue/queue.json" <<'JSON'
{
  "tasks": [
    {"id":"alpha","type":"extract","status":"done","batch":"alpha","file":"alpha.md"},
    {"id":"alpha-001","type":"claim","status":"completed","batch":"alpha","file":"alpha-001.md"},
    {"id":"beta-001","type":"claim","status":"pending","batch":"beta","file":"beta-001.md"},
    {"id":"gamma-001","type":"claim","status":"active","batch":"gamma","file":"gamma-001.md","claimed_at":"2020-01-01T00:00:00Z"},
    {"id":"delta-001","type":"claim","status":"blocked","batch":"delta","file":"delta-001.md","blocked_reason":"Missing source"},
    {"id":"epsilon-001","type":"claim","status":"pending","batch":"epsilon","file":"missing.md"}
  ]
}
JSON
printf '# Alpha\n' > "$vault/ops/queue/alpha.md"
printf '# Alpha 001\n' > "$vault/ops/queue/alpha-001.md"
printf '# Beta 001\n' > "$vault/ops/queue/beta-001.md"
printf '# Gamma 001\n' > "$vault/ops/queue/gamma-001.md"
printf '# Delta 001\n' > "$vault/ops/queue/delta-001.md"
printf '# Orphan\n' > "$vault/ops/queue/orphan.md"
cat > "$vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current
- [ ] Process queue batch alpha
- [ ] Review unrelated human task

## Completed

## Discoveries
EOF

output="$("$STATUS" "$vault")"
assert_contains "$output" "Queue hygiene status"
assert_contains "$output" "Pending: 2 | Active: 1 | Stale active: 1 | Blocked: 1 | Completed: 2"
assert_contains "$output" "Archivable batches: alpha"
assert_contains "$output" "Stale active tasks: gamma-001"
assert_contains "$output" "Orphan task files: ops/queue/orphan.md"
assert_contains "$output" "Missing task files: epsilon-001 -> ops/queue/missing.md"
assert_contains "$output" "Stale task stack: Process queue batch alpha"

json_output="$("$STATUS" "$vault" --format json)"
assert_contains "$json_output" '"archivable_batches"'
assert_contains "$json_output" '"alpha"'
assert_contains "$json_output" '"stale_active_tasks"'
assert_not_exists "$vault/ops/queue/archive/alpha.md"

printf 'PASS: queue-status-vault checks\n'
