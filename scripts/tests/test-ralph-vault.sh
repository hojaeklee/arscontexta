#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RALPH="$PROJECT_ROOT/plugins/hippocampusmd/scripts/ralph-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-ralph-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_vault="$tmp_dir/missing"
mkdir -p "$missing_vault"
missing_output="$("$RALPH" "$missing_vault" --dry-run)"
assert_contains "$missing_output" "Queue is empty"
assert_contains "$missing_output" "Use hippocampusmd-seed"

yaml_vault="$tmp_dir/yaml"
mkdir -p "$yaml_vault/ops/queue"
cat > "$yaml_vault/ops/queue/queue.yaml" <<'EOF'
phase_order:
  claim: [create, reflect, reweave, verify]
  enrichment: [enrich, reflect, reweave, verify]
tasks:
  - id: claim-001
    type: claim
    status: pending
    target: First Claim
    batch: alpha
    file: alpha-001.md
    current_phase: create
    completed_phases: []
  - id: claim-002
    type: claim
    status: pending
    target: Second Claim
    batch: alpha
    file: alpha-002.md
    current_phase: reflect
    completed_phases: [create]
  - id: claim-003
    type: claim
    status: blocked
    target: Blocked Claim
    batch: alpha
    current_phase: reflect
  - id: claim-004
    type: claim
    status: done
    target: Done Claim
    batch: alpha
    current_phase:
  - id: claim-005
    type: claim
    status: in_progress
    target: Active Claim
    batch: beta
    current_phase: create
  - id: claim-006
    type: claim
    status: pending
    target: Beta Claim
    batch: beta
    file: beta-006.md
    current_phase: verify
    completed_phases: [create, reflect, reweave]
EOF

yaml_output="$("$RALPH" "$yaml_vault" --dry-run --limit 2)"
assert_contains "$yaml_output" "Queue file: ops/queue/queue.yaml"
assert_contains "$yaml_output" "Total: 6 | Pending: 3 | Active: 1 | Blocked: 1 | Done: 1"
assert_contains "$yaml_output" "create: 1"
assert_contains "$yaml_output" "reflect: 1"
assert_contains "$yaml_output" "verify: 1"
assert_contains "$yaml_output" "1. claim-001 -- phase: create -- First Claim"
assert_contains "$yaml_output" "2. claim-002 -- phase: reflect -- Second Claim"
assert_contains "$yaml_output" "Estimated subagent spawns: 2"
assert_not_contains "$yaml_output" "Blocked Claim"
assert_not_contains "$yaml_output" "Active Claim"

filtered_output="$("$RALPH" "$yaml_vault" --dry-run --batch beta --type verify)"
assert_contains "$filtered_output" "1. claim-006 -- phase: verify -- Beta Claim"
assert_not_contains "$filtered_output" "claim-001"

advance_output="$("$RALPH" "$yaml_vault" --advance claim-001)"
assert_contains "$advance_output" "Advanced: claim-001"
assert_contains "$advance_output" "create -> reflect"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "current_phase: reflect"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "- create"

done_output="$("$RALPH" "$yaml_vault" --advance claim-006 --format json)"
assert_contains "$done_output" '"status": "done"'
assert_contains "$done_output" '"completed"'
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "status: done"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "completed:"

fail_output="$("$RALPH" "$yaml_vault" --fail claim-002 --reason "Source note missing")"
assert_contains "$fail_output" "Blocked: claim-002"
assert_contains "$fail_output" "Source note missing"
assert_contains "$(cat "$yaml_vault/ops/queue/queue.yaml")" "blocked_reason: Source note missing"

json_vault="$tmp_dir/json"
mkdir -p "$json_vault/ops/queue"
cat > "$json_vault/ops/queue/queue.json" <<'EOF'
{
  "phase_order": {
    "extract": ["extract"],
    "claim": ["create", "reflect", "reweave", "verify"]
  },
  "tasks": [
    {"id": "source-a", "type": "extract", "status": "pending", "target": "Source A", "file": "source-a.md", "current_phase": "extract"},
    {"id": "claim-json", "type": "claim", "status": "pending", "target": "JSON Claim", "batch": "json-batch", "file": "claim-json.md", "current_phase": "reflect", "completed_phases": ["create"]}
  ]
}
EOF
json_output="$("$RALPH" "$json_vault" --dry-run --format json --type reflect)"
assert_contains "$json_output" '"queue_file": "ops/queue/queue.json"'
assert_contains "$json_output" '"pending": 2'
assert_contains "$json_output" '"id": "claim-json"'
assert_not_contains "$json_output" '"id": "source-a"'

malformed_vault="$tmp_dir/malformed"
mkdir -p "$malformed_vault/ops/queue"
cat > "$malformed_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: bad
    status: pending
    current_phase: [oops
EOF
before="$(cat "$malformed_vault/ops/queue/queue.yaml")"
malformed_output="$(assert_exit 1 "$RALPH" "$malformed_vault" --dry-run)"
assert_contains "$malformed_output" "ERROR: Queue file is malformed"
after="$(cat "$malformed_vault/ops/queue/queue.yaml")"
[[ "$before" == "$after" ]] || fail "malformed queue should not be rewritten"

printf 'PASS: ralph-vault checks\n'
