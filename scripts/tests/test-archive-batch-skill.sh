#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-archive-batch/SKILL.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    fail "expected $file not to contain: $needle"
  fi
}

assert_file "$SKILL"
assert_contains "$SKILL" "name: hippocampusmd-archive-batch"
assert_contains "$SKILL" "Use when the user asks Codex to archive a completed HippocampusMD processing batch"
assert_contains "$SKILL" "complete-batch precondition"
assert_contains "$SKILL" "done"
assert_contains "$SKILL" "completed"
assert_contains "$SKILL" "ops/queue/queue.json"
assert_contains "$SKILL" "ops/queue/queue.yaml"
assert_contains "$SKILL" "ops/queue.yaml"
assert_contains "$SKILL" "archive_folder"
assert_contains "$SKILL" "ops/queue/archive/YYYY-MM-DD-BATCH"
assert_contains "$SKILL" "summary"
assert_contains "$SKILL" "BATCH-summary.md"
assert_contains "$SKILL" "no overwrites"
assert_contains "$SKILL" "preserving queue format"
assert_contains "$SKILL" "removes archived batch entries"
assert_contains "$SKILL" "plugins/hippocampusmd/scripts/archive-batch-vault.sh"
assert_contains "$SKILL" "Do not process research directly"
assert_contains "$SKILL" "Do not extract notes"
assert_contains "$SKILL" "Do not verify claims"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "AskUserQuestion"
assert_not_contains "$SKILL" "allowed-tools"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "slash-command"
assert_not_contains "$SKILL" '"/archive-batch"'
assert_not_contains "$SKILL" '`/archive-batch'

printf 'PASS: archive-batch skill checks\n'
