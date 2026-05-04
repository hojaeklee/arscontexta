#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RECONCILE="$PROJECT_ROOT/plugins/hippocampusmd/scripts/queue-reconcile-vault.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-queue-reconcile-test.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/ops/queue"
cat > "$vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: alpha
    status: done
    batch: alpha
    file: alpha.md
  - id: alpha-001
    status: completed
    batch: alpha
    file: alpha-001.md
  - id: beta-001
    status: pending
    batch: beta
    file: missing.md
  - id: gamma-001
    status: active
    batch: gamma
    file: gamma-001.md
    claimed_at: "2020-01-01T00:00:00Z"
EOF
printf '# Alpha\n' > "$vault/ops/queue/alpha.md"
printf '# Alpha 001\n' > "$vault/ops/queue/alpha-001.md"
printf '# Gamma 001\n' > "$vault/ops/queue/gamma-001.md"

dry_output="$("$RECONCILE" "$vault")"
assert_contains "$dry_output" "Mode: dry run"
assert_contains "$dry_output" "Archive recommendation: hippocampusmd-archive-batch --batch alpha"
assert_contains "$dry_output" "Would create archive directory"
assert_contains "$dry_output" "Would move completed task file ops/queue/alpha.md"
assert_contains "$dry_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/alpha.md" ]] || fail "dry-run must not move alpha.md"
[[ ! -f "$vault/ops/queue/archive/alpha/alpha-summary.md" ]] || fail "reconcile dry-run must not archive completed batch"

apply_output="$("$RECONCILE" "$vault" --apply)"
assert_contains "$apply_output" "Mode: apply"
assert_contains "$apply_output" "Archive recommendation: hippocampusmd-archive-batch --batch alpha"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha.md"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha-001.md"
assert_contains "$apply_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/archive/alpha/alpha.md" ]] || fail "alpha.md should move to deterministic archive"
[[ -f "$vault/ops/queue/archive/alpha/alpha-001.md" ]] || fail "alpha-001.md should move to deterministic archive"
[[ ! -f "$vault/ops/queue/archive/alpha/alpha-summary.md" ]] || fail "reconcile apply must not call archive-batch automatically"
[[ -f "$vault/ops/queue/gamma-001.md" ]] || fail "active task file must remain active"
assert_contains "$(cat "$vault/ops/queue/queue.yaml")" "beta-001"
assert_contains "$(cat "$vault/ops/queue/queue.yaml")" "alpha-001"
assert_not_contains "$(cat "$vault/ops/queue/queue.yaml")" "status: dropped"

second_apply="$("$RECONCILE" "$vault" --apply)"
assert_contains "$second_apply" "No deterministic repairs needed"

unsafe_vault="$tmp_dir/unsafe-vault"
mkdir -p "$unsafe_vault/ops/queue"
cat > "$unsafe_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: unsafe-001
    status: completed
    batch: ../../escape
    file: unsafe.md
EOF
printf '# Unsafe\n' > "$unsafe_vault/ops/queue/unsafe.md"
unsafe_output="$("$RECONCILE" "$unsafe_vault" --apply)"
assert_contains "$unsafe_output" "Skipped completed task file ops/queue/unsafe.md because archive segment is unsafe: ../../escape"
[[ -f "$unsafe_vault/ops/queue/unsafe.md" ]] || fail "unsafe source must remain active"
[[ ! -e "$unsafe_vault/escape" ]] || fail "unsafe batch must not create directory outside archive"
[[ ! -e "$unsafe_vault/ops/escape" ]] || fail "unsafe batch must not escape queue archive"

collision_vault="$tmp_dir/collision-vault"
mkdir -p "$collision_vault/ops/queue/archive/foo"
cat > "$collision_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: foo-001
    status: completed
    batch: foo
    file: foo.md
  - id: stale-001
    status: active
    batch: stale
    file: stale.md
    claimed_at: "2020-01-01T00:00:00Z"
EOF
printf '# Active Foo\n' > "$collision_vault/ops/queue/foo.md"
printf '# Archived Foo\n' > "$collision_vault/ops/queue/archive/foo/foo.md"
printf '# Stale\n' > "$collision_vault/ops/queue/stale.md"
collision_output="$("$RECONCILE" "$collision_vault" --apply)"
assert_contains "$collision_output" "Skipped completed task file ops/queue/foo.md because archive destination already exists ops/queue/archive/foo/foo.md"
[[ -f "$collision_vault/ops/queue/foo.md" ]] || fail "collision source must remain active"
assert_contains "$(cat "$collision_vault/ops/queue/archive/foo/foo.md")" "Archived Foo"

json_output="$("$RECONCILE" "$collision_vault" --format json)"
ruby -rjson -e '
data = JSON.parse(ARGF.read)
actions = data.fetch("actions")
unless data.fetch("mode") == "dry run"
  warn "FAIL: expected JSON mode to be dry run"
  exit 1
end
unless actions.any? { |action| action.fetch("type") == "skipped_completed_task_file" && action.fetch("reason") == "destination_exists" }
  warn "FAIL: expected JSON skipped collision action"
  exit 1
end
unless data.fetch("proposals").any? { |proposal| proposal.fetch("type") == "stale_active_task" && proposal.fetch("task_id") == "stale-001" }
  warn "FAIL: expected JSON stale active proposal"
  exit 1
end
' <<< "$json_output"

printf 'PASS: queue-reconcile-vault checks\n'
