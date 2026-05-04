#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-reseed/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-reseed"
assert_contains "$SKILL" "Use when the user asks Codex to analyze HippocampusMD structural drift"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "dimension incoherence"
assert_contains "$SKILL" "vocabulary mismatch"
assert_contains "$SKILL" "three-space boundaries"
assert_contains "$SKILL" "template divergence"
assert_contains "$SKILL" "MOC hierarchy"
assert_contains "$SKILL" "none, aligned, compensated, incoherent, or stagnant"
assert_contains "$SKILL" "notes"
assert_contains "$SKILL" "MOCs"
assert_contains "$SKILL" "templates"
assert_contains "$SKILL" "self space"
assert_contains "$SKILL" "inbox"
assert_contains "$SKILL" "ops files"
assert_contains "$SKILL" "health history"
assert_contains "$SKILL" "observations"
assert_contains "$SKILL" "tensions"
assert_contains "$SKILL" "methodology"
assert_contains "$SKILL" "interaction-constraints.md"
assert_contains "$SKILL" "derivation-validation.md"
assert_contains "$SKILL" "three-spaces.md"
assert_contains "$SKILL" "failure-modes.md"
assert_contains "$SKILL" "dimension-claim-map.md"
assert_contains "$SKILL" "evolution-lifecycle.md"
assert_contains "$SKILL" "self-space.md"
assert_contains "$SKILL" "kernel.yaml"
assert_contains "$SKILL" "analysis/report mode"
assert_contains "$SKILL" '`--analysis-only`'
assert_contains "$SKILL" "never deletes notes, memory, or user content"
assert_contains "$SKILL" "content preservation"
assert_contains "$SKILL" "content impact"
assert_contains "$SKILL" "risk"
assert_contains "$SKILL" "rollback"
assert_contains "$SKILL" "validation expectations"
assert_contains "$SKILL" "explicit approval before"
assert_contains "$SKILL" "restructuring"
assert_contains "$SKILL" "folder moves"
assert_contains "$SKILL" "template edits"
assert_contains "$SKILL" "derivation rewrites"
assert_contains "$SKILL" "MOC changes"
assert_contains "$SKILL" "self-space updates"
assert_contains "$SKILL" "broad note edits"
assert_contains "$SKILL" "kernel"
assert_contains "$SKILL" "link"
assert_contains "$SKILL" "schema"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "three-space"
assert_contains "$SKILL" "hippocampusmd-architect"
assert_contains "$SKILL" "hippocampusmd-refactor"
assert_contains "$SKILL" "Codex file workflows"
assert_contains "$SKILL" "Use Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/reseed"

printf 'PASS: reseed skill checks\n'
