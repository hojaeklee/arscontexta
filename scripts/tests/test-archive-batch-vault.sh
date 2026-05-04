#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
ARCHIVE="$PROJECT_ROOT/plugins/hippocampusmd/scripts/archive-batch-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-archive-batch-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_vault="$tmp_dir/missing"
mkdir -p "$missing_vault"
missing_output="$(assert_exit 1 "$ARCHIVE" "$missing_vault" --batch absent)"
assert_contains "$missing_output" "ERROR: Queue file not found"

malformed_vault="$tmp_dir/malformed"
mkdir -p "$malformed_vault/ops/queue"
cat > "$malformed_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: bad
    status: [oops
EOF
malformed_before="$(cat "$malformed_vault/ops/queue/queue.yaml")"
malformed_output="$(assert_exit 1 "$ARCHIVE" "$malformed_vault" --batch bad)"
assert_contains "$malformed_output" "ERROR: Queue file is malformed"
malformed_after="$(cat "$malformed_vault/ops/queue/queue.yaml")"
[[ "$malformed_before" == "$malformed_after" ]] || fail "malformed queue should not be rewritten"

incomplete_vault="$tmp_dir/incomplete"
mkdir -p "$incomplete_vault/ops/queue/archive/2026-05-03-alpha"
cat > "$incomplete_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: alpha
    type: extract
    status: done
    file: alpha.md
    archive_folder: ops/queue/archive/2026-05-03-alpha
  - id: alpha-001
    type: claim
    status: pending
    batch: alpha
    file: alpha-001.md
EOF
cat > "$incomplete_vault/ops/queue/alpha.md" <<'EOF'
# Alpha extract
EOF
cat > "$incomplete_vault/ops/queue/alpha-001.md" <<'EOF'
# Alpha claim
EOF
incomplete_before="$(cat "$incomplete_vault/ops/queue/queue.yaml")"
incomplete_output="$(assert_exit 1 "$ARCHIVE" "$incomplete_vault" --batch alpha)"
assert_contains "$incomplete_output" "ERROR: Batch alpha is not complete"
[[ "$incomplete_before" == "$(cat "$incomplete_vault/ops/queue/queue.yaml")" ]] || fail "incomplete queue should not change"
[[ -f "$incomplete_vault/ops/queue/alpha.md" ]] || fail "incomplete task file should remain active"
[[ -f "$incomplete_vault/ops/queue/alpha-001.md" ]] || fail "incomplete claim file should remain active"

yaml_vault="$tmp_dir/yaml"
mkdir -p "$yaml_vault/ops/queue/archive/2026-05-03-alpha"
cat > "$yaml_vault/ops/queue/queue.yaml" <<'EOF'
phase_order:
  claim:
    - create
    - verify
tasks:
  - id: alpha
    type: extract
    status: done
    file: alpha.md
    source: ops/queue/archive/2026-05-03-alpha/source.md
    archive_folder: ops/queue/archive/2026-05-03-alpha
  - id: alpha-001
    type: claim
    status: completed
    batch: alpha
    file: alpha-001.md
    target: Alpha One
  - id: beta-001
    type: claim
    status: pending
    batch: beta
    file: beta-001.md
    target: Beta One
EOF
cat > "$yaml_vault/ops/queue/alpha.md" <<'EOF'
# Alpha extract
EOF
cat > "$yaml_vault/ops/queue/alpha-001.md" <<'EOF'
# Alpha One
EOF
cat > "$yaml_vault/ops/queue/beta-001.md" <<'EOF'
# Beta One
EOF
yaml_output="$("$ARCHIVE" "$yaml_vault" --batch alpha)"
assert_contains "$yaml_output" "Archived batch: alpha"
assert_contains "$yaml_output" "Tasks archived: 2"
assert_contains "$yaml_output" "Summary: ops/queue/archive/2026-05-03-alpha/alpha-summary.md"
[[ -f "$yaml_vault/ops/queue/archive/2026-05-03-alpha/alpha.md" ]] || fail "extract task should move to archive"
[[ -f "$yaml_vault/ops/queue/archive/2026-05-03-alpha/alpha-001.md" ]] || fail "claim task should move to archive"
[[ -f "$yaml_vault/ops/queue/archive/2026-05-03-alpha/alpha-summary.md" ]] || fail "summary should be written"
[[ ! -f "$yaml_vault/ops/queue/alpha.md" ]] || fail "extract task should leave active queue folder"
[[ ! -f "$yaml_vault/ops/queue/alpha-001.md" ]] || fail "claim task should leave active queue folder"
[[ -f "$yaml_vault/ops/queue/beta-001.md" ]] || fail "unrelated task file should remain active"
queue_after="$(cat "$yaml_vault/ops/queue/queue.yaml")"
assert_not_contains "$queue_after" "alpha-001"
assert_contains "$queue_after" "beta-001"
assert_contains "$queue_after" "phase_order:"
summary_text="$(cat "$yaml_vault/ops/queue/archive/2026-05-03-alpha/alpha-summary.md")"
assert_contains "$summary_text" "# Batch Summary: alpha"
assert_contains "$summary_text" "Alpha One"

json_vault="$tmp_dir/json"
mkdir -p "$json_vault/ops/queue/archive/2026-05-03-gamma"
cat > "$json_vault/ops/queue/queue.json" <<'EOF'
{
  "tasks": [
    {"id": "gamma", "type": "extract", "status": "done", "file": "gamma.md", "archive_folder": "ops/queue/archive/2026-05-03-gamma"},
    {"id": "gamma-001", "type": "claim", "status": "done", "batch": "gamma", "file": "gamma-001.md", "target": "Gamma One"},
    {"id": "delta-001", "type": "claim", "status": "pending", "batch": "delta", "file": "delta-001.md", "target": "Delta One"}
  ]
}
EOF
cat > "$json_vault/ops/queue/gamma.md" <<'EOF'
# Gamma extract
EOF
cat > "$json_vault/ops/queue/gamma-001.md" <<'EOF'
# Gamma One
EOF
cat > "$json_vault/ops/queue/delta-001.md" <<'EOF'
# Delta One
EOF
json_output="$("$ARCHIVE" "$json_vault" --batch gamma --format json)"
assert_contains "$json_output" '"batch": "gamma"'
assert_contains "$json_output" '"tasks_archived": 2'
assert_contains "$json_output" '"queue_file": "ops/queue/queue.json"'
json_queue_after="$(cat "$json_vault/ops/queue/queue.json")"
assert_contains "$json_queue_after" '"tasks"'
assert_contains "$json_queue_after" '"delta-001"'
assert_not_contains "$json_queue_after" '"gamma-001"'

partial_vault="$tmp_dir/partial"
mkdir -p "$partial_vault/ops/queue/archive/2026-05-03-theta"
cat > "$partial_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: theta
    type: extract
    status: done
    file: theta.md
    archive_folder: ops/queue/archive/2026-05-03-theta
  - id: theta-001
    type: claim
    status: completed
    batch: theta
    file: theta-001.md
    archive_folder: ops/queue/archive/2026-05-03-theta
EOF
cat > "$partial_vault/ops/queue/archive/2026-05-03-theta/theta.md" <<'EOF'
# Already moved theta
EOF
cat > "$partial_vault/ops/queue/theta-001.md" <<'EOF'
# Theta claim
EOF
partial_output="$("$ARCHIVE" "$partial_vault" --batch theta)"
assert_contains "$partial_output" "Already archived task file: ops/queue/archive/2026-05-03-theta/theta.md"
assert_contains "$partial_output" "Task files moved: 1"
assert_not_contains "$(cat "$partial_vault/ops/queue/queue.yaml")" "theta-001"
[[ -f "$partial_vault/ops/queue/archive/2026-05-03-theta/theta.md" ]] || fail "already archived task should remain archived"
[[ -f "$partial_vault/ops/queue/archive/2026-05-03-theta/theta-001.md" ]] || fail "remaining task should move to archive"
[[ ! -f "$partial_vault/ops/queue/theta-001.md" ]] || fail "remaining task should leave active queue folder"

missing_task_vault="$tmp_dir/missing-task"
mkdir -p "$missing_task_vault/ops/queue/archive/2026-05-03-eta"
cat > "$missing_task_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: eta
    type: extract
    status: done
    file: eta.md
    archive_folder: ops/queue/archive/2026-05-03-eta
  - id: eta-001
    type: claim
    status: completed
    batch: eta
    file: eta-001.md
    archive_folder: ops/queue/archive/2026-05-03-eta
EOF
cat > "$missing_task_vault/ops/queue/eta-001.md" <<'EOF'
# Eta claim
EOF
missing_task_before="$(cat "$missing_task_vault/ops/queue/queue.yaml")"
missing_task_output="$(assert_exit 1 "$ARCHIVE" "$missing_task_vault" --batch eta)"
assert_contains "$missing_task_output" "ERROR: Task file missing from active queue and archive"
assert_contains "$missing_task_output" "- eta: ops/queue/eta.md or ops/queue/archive/2026-05-03-eta/eta.md"
[[ "$missing_task_before" == "$(cat "$missing_task_vault/ops/queue/queue.yaml")" ]] || fail "missing task queue should not change"
[[ -f "$missing_task_vault/ops/queue/eta-001.md" ]] || fail "missing task failure should preserve active files"
[[ ! -f "$missing_task_vault/ops/queue/archive/2026-05-03-eta/eta-001.md" ]] || fail "missing task failure should not move remaining files"

collision_vault="$tmp_dir/collision"
mkdir -p "$collision_vault/ops/queue/archive/2026-05-03-zeta"
cat > "$collision_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: zeta
    type: extract
    status: done
    file: zeta.md
    archive_folder: ops/queue/archive/2026-05-03-zeta
EOF
cat > "$collision_vault/ops/queue/zeta.md" <<'EOF'
# Zeta extract
EOF
cat > "$collision_vault/ops/queue/archive/2026-05-03-zeta/zeta.md" <<'EOF'
# Existing zeta
EOF
cat > "$collision_vault/ops/queue/archive/2026-05-03-zeta/zeta-summary.md" <<'EOF'
# Existing summary
EOF
collision_before="$(cat "$collision_vault/ops/queue/queue.yaml")"
collision_output="$(assert_exit 1 "$ARCHIVE" "$collision_vault" --batch zeta)"
assert_contains "$collision_output" "ERROR: Archive destination already exists"
[[ "$collision_before" == "$(cat "$collision_vault/ops/queue/queue.yaml")" ]] || fail "collision queue should not change"
[[ "$(cat "$collision_vault/ops/queue/archive/2026-05-03-zeta/zeta.md")" == "# Existing zeta" ]] || fail "collision should not overwrite archived task"
[[ "$(cat "$collision_vault/ops/queue/archive/2026-05-03-zeta/zeta-summary.md")" == "# Existing summary" ]] || fail "collision should not overwrite summary"
[[ -f "$collision_vault/ops/queue/zeta.md" ]] || fail "active task should remain after collision"

printf 'PASS: archive-batch-vault checks\n'
