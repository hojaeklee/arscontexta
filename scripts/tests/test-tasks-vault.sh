#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
TASKS="$PROJECT_ROOT/scripts/tasks-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-tasks-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/ops/queue"

missing_output="$("$TASKS" "$vault" --status)"
assert_contains "$missing_output" "Task stack: missing"
assert_contains "$missing_output" "No task stack found"
[[ ! -f "$vault/ops/tasks.md" ]] || fail "status should not create ops/tasks.md"

add_output="$("$TASKS" "$vault" --add "Review inbox notes")"
assert_contains "$add_output" "Added to task stack: Review inbox notes"
assert_contains "$add_output" "1. [ ] Review inbox notes"
assert_contains "$(cat "$vault/ops/tasks.md")" "## Current"

"$TASKS" "$vault" --add "Process queued claims" >/dev/null
cat >> "$vault/ops/tasks.md" <<'EOF'
- [ ] This line is outside canonical sections
EOF

cat > "$vault/ops/tasks.md" <<'EOF'
# Task Stack

Some note before task sections.

## Active
- [ ] Review inbox notes
- [ ] Process queued claims
- [ ] Validate new note

## Completed
- [x] Seed source batch (2026-04-20)

## Discoveries
- [[index]] may need splitting
- Connect [[alpha]] and [[beta]]
EOF

status_output="$("$TASKS" "$vault" --status)"
assert_contains "$status_output" "1. [ ] Review inbox notes"
assert_contains "$status_output" "2. [ ] Process queued claims"
assert_contains "$status_output" "Seed source batch"
assert_contains "$status_output" "[[index]] may need splitting"

discoveries_output="$("$TASKS" "$vault" --discoveries)"
assert_contains "$discoveries_output" "Discoveries:"
assert_contains "$discoveries_output" "Connect [[alpha]] and [[beta]]"
assert_not_contains "$discoveries_output" "Process queued claims"

done_output="$("$TASKS" "$vault" --done 2)"
assert_contains "$done_output" "Completed: Process queued claims"
assert_contains "$(cat "$vault/ops/tasks.md")" "- [x] Process queued claims"
assert_not_contains "$(sed -n '/## Current/,/## Completed/p' "$vault/ops/tasks.md")" "Process queued claims"

drop_output="$("$TASKS" "$vault" --drop 2)"
assert_contains "$drop_output" "Dropped: Validate new note"
assert_not_contains "$(cat "$vault/ops/tasks.md")" "Validate new note"

"$TASKS" "$vault" --add "Third task" >/dev/null
"$TASKS" "$vault" --add "Fourth task" >/dev/null
reorder_output="$("$TASKS" "$vault" --reorder 3 1)"
assert_contains "$reorder_output" "Moved: Fourth task"
current_section="$(sed -n '/## Current/,/## Completed/p' "$vault/ops/tasks.md")"
first_current="$(printf '%s\n' "$current_section" | grep -F -- '- [ ]' | sed -n '1p')"
[[ "$first_current" == "- [ ] Fourth task" ]] || fail "expected Fourth task to move to top, got: $first_current"

json_vault="$tmp_dir/json-vault"
mkdir -p "$json_vault/ops/queue"
cat > "$json_vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current
- [ ] Human priority

## Completed

## Discoveries
EOF
cat > "$json_vault/ops/queue/queue.json" <<'EOF'
{
  "tasks": [
    {"id": "claim-001", "status": "pending", "current_phase": "create", "target": "Claim 001", "batch": "batch-a"},
    {"id": "claim-002", "status": "in_progress", "current_phase": "reflect", "target": "Claim 002", "batch": "batch-a"},
    {"id": "claim-003", "status": "blocked", "current_phase": "verify", "target": "Claim 003", "batch": "batch-b"},
    {"id": "claim-004", "status": "done", "current_phase": "verify", "target": "Claim 004", "batch": "batch-c"},
    {"id": "claim-005", "status": "completed", "current_phase": "verify", "target": "Claim 005", "batch": "batch-c"}
  ]
}
EOF
json_output="$("$TASKS" "$json_vault" --status)"
assert_contains "$json_output" "Pending: 1 | Active: 1 | Blocked: 1 | Completed: 2"
assert_contains "$json_output" "claim-001: pending / create -- Claim 001 (batch: batch-a)"
assert_contains "$json_output" "Archivable batches: batch-c"

json_machine="$("$TASKS" "$json_vault" --status --format json)"
assert_contains "$json_machine" '"pending": 1'
assert_contains "$json_machine" '"blocked": 1'

yaml_vault="$tmp_dir/yaml-vault"
mkdir -p "$yaml_vault/ops/queue"
cat > "$yaml_vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current

## Completed

## Discoveries
EOF
cat > "$yaml_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: yaml-001
    status: pending
    current_phase: create
    target: YAML Claim
    batch: yaml-batch
  - id: yaml-002
    status: done
    current_phase: verify
    target: YAML Done
    batch: yaml-done
EOF
yaml_output="$("$TASKS" "$yaml_vault" --status)"
assert_contains "$yaml_output" "Queue file: ops/queue/queue.yaml"
assert_contains "$yaml_output" "Pending: 1"
assert_contains "$yaml_output" "yaml-001: pending / create -- YAML Claim"
assert_contains "$yaml_output" "Archivable batches: yaml-done"

printf 'PASS: tasks-vault checks\n'
