#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
PIPELINE="$PROJECT_ROOT/scripts/pipeline-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-pipeline-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_vault="$tmp_dir/missing"
mkdir -p "$missing_vault"
missing_output="$(assert_exit 1 "$PIPELINE" "$missing_vault" --plan --file missing.md)"
assert_contains "$missing_output" "ERROR: Source file not found"

plan_vault="$tmp_dir/plan"
mkdir -p "$plan_vault/inbox" "$plan_vault/ops/queue/archive"
cat > "$plan_vault/inbox/New Source.md" <<'EOF'
# New Source
EOF
plan_output="$("$PIPELINE" "$plan_vault" --plan --file "New Source.md")"
assert_contains "$plan_output" "Pipeline plan"
assert_contains "$plan_output" "Source: inbox/New Source.md"
assert_contains "$plan_output" "Batch: new-source"
assert_contains "$plan_output" "Queue status: unseeded"
assert_contains "$plan_output" "Next action: run arscontexta-seed"
assert_contains "$plan_output" "Then: run arscontexta-ralph"
[[ ! -f "$plan_vault/ops/queue/queue.yaml" ]] || fail "plan should not create queue state"

cat > "$plan_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: new-source
    type: extract
    status: pending
    source: ops/queue/archive/2026-05-03-new-source/New Source.md
    file: new-source.md
    current_phase: extract
EOF
queued_plan="$("$PIPELINE" "$plan_vault" --plan --file "New Source.md" --format json)"
assert_contains "$queued_plan" '"batch": "new-source"'
assert_contains "$queued_plan" '"queue_status": "already queued"'
assert_contains "$queued_plan" '"next_action": "run arscontexta-ralph --batch new-source"'

status_vault="$tmp_dir/status"
mkdir -p "$status_vault/ops/queue"
cat > "$status_vault/ops/queue/queue.json" <<'EOF'
{
  "tasks": [
    {"id": "alpha", "type": "extract", "status": "done", "source": "ops/queue/archive/alpha/source.md", "file": "alpha.md", "current_phase": null},
    {"id": "alpha-001", "type": "claim", "status": "pending", "target": "Alpha One", "batch": "alpha", "file": "alpha-001.md", "current_phase": "create"},
    {"id": "alpha-002", "type": "claim", "status": "blocked", "target": "Alpha Two", "batch": "alpha", "file": "alpha-002.md", "current_phase": "reflect", "blocked_reason": "Missing source"},
    {"id": "alpha-003", "type": "claim", "status": "in_progress", "target": "Alpha Three", "batch": "alpha", "file": "alpha-003.md", "current_phase": "verify"},
    {"id": "alpha-004", "type": "claim", "status": "done", "target": "Alpha Four", "batch": "alpha", "file": "alpha-004.md", "current_phase": null},
    {"id": "beta-001", "type": "claim", "status": "pending", "target": "Beta One", "batch": "beta", "file": "beta-001.md", "current_phase": "create"}
  ]
}
EOF
status_output="$("$PIPELINE" "$status_vault" --status --batch alpha)"
assert_contains "$status_output" "Batch: alpha"
assert_contains "$status_output" "Total: 5 | Pending: 1 | Active: 1 | Blocked: 1 | Done: 2"
assert_contains "$status_output" "create: 1"
assert_contains "$status_output" "verify: 1"
assert_contains "$status_output" "Blocked tasks:"
assert_contains "$status_output" "alpha-002 -- reflect -- Missing source"
assert_contains "$status_output" "Next action: resolve blocked tasks, then run arscontexta-ralph --batch alpha"
assert_not_contains "$status_output" "beta-001"

status_json="$("$PIPELINE" "$status_vault" --status --batch alpha --format json)"
assert_contains "$status_json" '"batch": "alpha"'
assert_contains "$status_json" '"pending": 1'
assert_contains "$status_json" '"blocked": 1'
assert_contains "$status_json" '"ready_to_archive": false'
assert_contains "$status_json" '"next_action": "resolve blocked tasks, then run arscontexta-ralph --batch alpha"'

ready_false="$("$PIPELINE" "$status_vault" --ready-to-archive --batch alpha)"
assert_contains "$ready_false" "Ready to archive: no"

ready_vault="$tmp_dir/ready"
mkdir -p "$ready_vault/ops/queue"
cat > "$ready_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: gamma-001
    type: claim
    status: done
    target: Gamma One
    batch: gamma
  - id: gamma-002
    type: claim
    status: completed
    target: Gamma Two
    batch: gamma
EOF
ready_output="$("$PIPELINE" "$ready_vault" --ready-to-archive --batch gamma --format json)"
assert_contains "$ready_output" '"batch": "gamma"'
assert_contains "$ready_output" '"ready_to_archive": true'
assert_contains "$ready_output" '"next_action": "run arscontexta-archive-batch --batch gamma"'

malformed_vault="$tmp_dir/malformed"
mkdir -p "$malformed_vault/ops/queue"
cat > "$malformed_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: bad
    status: pending
    current_phase: [oops
EOF
before="$(cat "$malformed_vault/ops/queue/queue.yaml")"
malformed_output="$(assert_exit 1 "$PIPELINE" "$malformed_vault" --status --batch bad)"
assert_contains "$malformed_output" "ERROR: Queue file is malformed"
after="$(cat "$malformed_vault/ops/queue/queue.yaml")"
[[ "$before" == "$after" ]] || fail "malformed queue should not be rewritten"

printf 'PASS: pipeline-vault checks\n'
