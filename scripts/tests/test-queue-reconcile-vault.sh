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
assert_contains "$dry_output" "Would create archive directory"
assert_contains "$dry_output" "Would move completed task file ops/queue/alpha.md"
assert_contains "$dry_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/alpha.md" ]] || fail "dry-run must not move alpha.md"

apply_output="$("$RECONCILE" "$vault" --apply)"
assert_contains "$apply_output" "Mode: apply"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha.md"
assert_contains "$apply_output" "Moved completed task file ops/queue/alpha-001.md"
assert_contains "$apply_output" "Proposal: review stale active task gamma-001"
[[ -f "$vault/ops/queue/archive/alpha/alpha.md" ]] || fail "alpha.md should move to deterministic archive"
[[ -f "$vault/ops/queue/archive/alpha/alpha-001.md" ]] || fail "alpha-001.md should move to deterministic archive"
[[ -f "$vault/ops/queue/gamma-001.md" ]] || fail "active task file must remain active"
assert_contains "$(cat "$vault/ops/queue/queue.yaml")" "beta-001"
assert_not_contains "$(cat "$vault/ops/queue/queue.yaml")" "status: dropped"

second_apply="$("$RECONCILE" "$vault" --apply)"
assert_contains "$second_apply" "No deterministic repairs needed"

printf 'PASS: queue-reconcile-vault checks\n'
