#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-upgrade/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-upgrade"
assert_contains "$SKILL" "Use when the user asks Codex to compare an existing HippocampusMD vault"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/generation-manifest.yaml"
assert_contains "$SKILL" "all generated skills"
assert_contains "$SKILL" '`--all`'
assert_contains "$SKILL" "one named skill"
assert_contains "$SKILL" "installed/generated vault skills"
assert_contains "$SKILL" "user-modified"
assert_contains "$SKILL" "plugins/hippocampusmd/methodology/"
assert_contains "$SKILL" "plugins/hippocampusmd/reference/"
assert_contains "$SKILL" "methodology comparison"
assert_contains "$SKILL" "not hash comparison"
assert_contains "$SKILL" "current"
assert_contains "$SKILL" "enhancement"
assert_contains "$SKILL" "correction"
assert_contains "$SKILL" "extension"
assert_contains "$SKILL" "rationale"
assert_contains "$SKILL" "local file references"
assert_contains "$SKILL" "risk"
assert_contains "$SKILL" "reversibility"
assert_contains "$SKILL" "user-modification"
assert_contains "$SKILL" "explicit approval before"
assert_contains "$SKILL" "skill rewrite"
assert_contains "$SKILL" "methodology update"
assert_contains "$SKILL" "archive creation"
assert_contains "$SKILL" "generation-manifest update"
assert_contains "$SKILL" "broad vault change"
assert_contains "$SKILL" "Never silently overwrite user-modified skills"
assert_contains "$SKILL" "hippocampusmd-architect"
assert_contains "$SKILL" "hippocampusmd-refactor"
assert_contains "$SKILL" "hippocampusmd-reseed"
assert_contains "$SKILL" "plugin/meta-skill updates remain a plugin release concern"
assert_contains "$SKILL" "Codex file workflows"
assert_contains "$SKILL" "Use Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/upgrade"

printf 'PASS: upgrade skill checks\n'
