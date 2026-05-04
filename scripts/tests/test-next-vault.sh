#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
NEXT="$PROJECT_ROOT/plugins/hippocampusmd/scripts/next-vault.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected file not to exist: $1"
}

make_vault() {
  local vault="$1"
  mkdir -p "$vault/notes" "$vault/inbox" "$vault/ops/queue" "$vault/ops/observations" "$vault/ops/tensions" "$vault/ops/health" "$vault/self"
  touch "$vault/.hippocampusmd"
  cat > "$vault/ops/derivation-manifest.md" <<'EOF'
---
vocabulary:
  notes: notes
  inbox: inbox
  note: claim
  reduce: reduce
  reweave: reweave
  rethink: rethink
  ralph: ralph
---
EOF
  cat > "$vault/ops/config.yaml" <<'EOF'
self_evolution:
  observation_threshold: 10
  tension_threshold: 5
EOF
}

add_notes() {
  local vault="$1"
  local count="$2"
  local i
  for i in $(seq 1 "$count"); do
    printf '# Note %s\n' "$i" > "$vault/notes/note-$i.md"
  done
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-next-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

task_vault="$tmp_dir/task-vault"
make_vault "$task_vault"
add_notes "$task_vault" 8
cat > "$task_vault/self/goals.md" <<'EOF'
# Goals
- Grow the research graph
EOF
cat > "$task_vault/ops/tasks.md" <<'EOF'
# Task Stack

## Current
- [ ] Finish explicit user task

## Completed

## Discoveries
EOF
mkdir -p "$task_vault/inbox"
for i in $(seq 1 7); do printf '# Inbox %s\n' "$i" > "$task_vault/inbox/item-$i.md"; done
task_output="$("$NEXT" "$task_vault")"
assert_contains "$task_output" "Recommended: Finish explicit user task"
assert_contains "$task_output" "task stack priorities override automated signals"

missing_goals="$tmp_dir/missing-goals"
make_vault "$missing_goals"
add_notes "$missing_goals" 8
goals_output="$("$NEXT" "$missing_goals")"
assert_contains "$goals_output" "Recommended: Create ops/goals.md"

early_vault="$tmp_dir/early-vault"
make_vault "$early_vault"
add_notes "$early_vault" 2
cat > "$early_vault/self/goals.md" <<'EOF'
# Goals
- Build the graph
EOF
printf '# First capture\n' > "$early_vault/inbox/first.md"
early_output="$("$NEXT" "$early_vault")"
assert_contains "$early_output" "Recommended: reduce inbox/first.md"
assert_contains "$early_output" "early-stage vault"

inbox_vault="$tmp_dir/inbox-vault"
make_vault "$inbox_vault"
add_notes "$inbox_vault" 8
cat > "$inbox_vault/self/goals.md" <<'EOF'
# Goals
- Process captured sources
EOF
for i in $(seq 1 6); do printf '# Inbox %s\n' "$i" > "$inbox_vault/inbox/item-$i.md"; done
touch -t 202001010000 "$inbox_vault/inbox/item-1.md"
inbox_output="$("$NEXT" "$inbox_vault")"
assert_contains "$inbox_output" "Recommended: reduce inbox/item-1.md"
assert_contains "$inbox_output" "The inbox has 6 items"

rethink_vault="$tmp_dir/rethink-vault"
make_vault "$rethink_vault"
add_notes "$rethink_vault" 8
cat > "$rethink_vault/self/goals.md" <<'EOF'
# Goals
- Improve methodology
EOF
for i in $(seq 1 10); do
  printf '%s\n' '---' 'status: pending' '---' "# Observation $i" > "$rethink_vault/ops/observations/obs-$i.md"
done
rethink_output="$("$NEXT" "$rethink_vault")"
assert_contains "$rethink_output" "Recommended: rethink"
assert_contains "$rethink_output" "pending observations"

queue_vault="$tmp_dir/queue-vault"
make_vault "$queue_vault"
add_notes "$queue_vault" 8
cat > "$queue_vault/self/goals.md" <<'EOF'
# Goals
- Move pipeline forward
EOF
{
  printf '{ "tasks": [\n'
  for i in $(seq 1 11); do
    comma=","
    [[ "$i" -eq 11 ]] && comma=""
    printf '  {"id":"claim-%03d","status":"pending","current_phase":"reflect","target":"Claim %03d"}%s\n' "$i" "$i" "$comma"
  done
  printf ']}\n'
} > "$queue_vault/ops/queue/queue.json"
queue_output="$("$NEXT" "$queue_vault")"
assert_contains "$queue_output" "Recommended: ralph 5"
assert_contains "$queue_output" "11 queue tasks are pending"

blocked_vault="$tmp_dir/blocked-vault"
make_vault "$blocked_vault"
add_notes "$blocked_vault" 8
cat > "$blocked_vault/self/goals.md" <<'EOF'
# Goals
- Clear blockers
EOF
cat > "$blocked_vault/ops/queue/queue.json" <<'EOF'
{"tasks":[{"id":"claim-blocked","status":"blocked","current_phase":"verify","target":"Blocked Claim"}]}
EOF
blocked_output="$("$NEXT" "$blocked_vault")"
assert_contains "$blocked_output" "Recommended: Resolve blocked queue task claim-blocked"
assert_contains "$blocked_output" "blocked queue task stops downstream processing"

health_vault="$tmp_dir/health-vault"
make_vault "$health_vault"
add_notes "$health_vault" 8
cat > "$health_vault/self/goals.md" <<'EOF'
# Goals
- Keep graph healthy
EOF
cat > "$health_vault/ops/health/2026-04-26.md" <<'EOF'
# Health
FAIL Broken primary links found.
EOF
health_output="$("$NEXT" "$health_vault")"
assert_contains "$health_output" "Health: ops/health/2026-04-26.md"
assert_contains "$health_output" "Recommended: Review ops/health/2026-04-26.md"

json_output="$("$NEXT" "$inbox_vault" --format json)"
assert_contains "$json_output" '"priority": "session"'
assert_contains "$json_output" '"recommendation": "reduce inbox/item-1.md"'
assert_contains "$json_output" '"inbox": 6'

readonly_vault="$tmp_dir/readonly-vault"
make_vault "$readonly_vault"
add_notes "$readonly_vault" 8
cat > "$readonly_vault/self/goals.md" <<'EOF'
# Goals
- Stay read only
EOF
"$NEXT" "$readonly_vault" >/dev/null
assert_not_exists "$readonly_vault/ops/next-log.md"

printf 'PASS: next-vault checks\n'
