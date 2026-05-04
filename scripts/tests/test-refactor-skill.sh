#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-refactor/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-refactor"
assert_contains "$SKILL" "Use when the user asks Codex to pla HippocampusMD vault restructuring"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "Cannot refactor without both"
assert_contains "$SKILL" "all-dimension review"
assert_contains "$SKILL" "single-dimension focus"
assert_contains "$SKILL" '`--dry-run`'
assert_contains "$SKILL" "report-only"
assert_contains "$SKILL" "dimension"
assert_contains "$SKILL" "feature flag"
assert_contains "$SKILL" "affected artifacts"
assert_contains "$SKILL" "content impact"
assert_contains "$SKILL" "risk"
assert_contains "$SKILL" "reversibility"
assert_contains "$SKILL" "validation"
assert_contains "$SKILL" "interaction constraints"
assert_contains "$SKILL" "plugins/hippocampusmd/reference/interaction-constraints.md"
assert_contains "$SKILL" "explicit approval before"
assert_contains "$SKILL" "file moves"
assert_contains "$SKILL" "rewrites"
assert_contains "$SKILL" "content migrations"
assert_contains "$SKILL" "template edits"
assert_contains "$SKILL" "config/derivation updates"
assert_contains "$SKILL" "hook edits"
assert_contains "$SKILL" "broad note changes"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" "Do not auto-regenerate skills"
assert_contains "$SKILL" "destructive migrations"
assert_contains "$SKILL" "hippocampusmd-architect"
assert_contains "$SKILL" "report-only restructuring plan"
assert_contains "$SKILL" "Codex file workflows"
assert_contains "$SKILL" "Use Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/refactor"

printf 'PASS: refactor skill checks\n'
