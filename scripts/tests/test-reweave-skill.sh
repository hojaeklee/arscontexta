#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-reweave/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-reweave"
assert_contains "$SKILL" "Use when the user asks Codex to revisit older HippocampusMD notes"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "specific note"
assert_contains "$SKILL" '`sparse` notes'
assert_contains "$SKILL" '`recent` notes or `--since Nd`'
assert_contains "$SKILL" "no argument"
assert_contains "$SKILL" "Read target notes fully"
assert_contains "$SKILL" "Use local search before optional semantic tooling"
assert_contains "$SKILL" "file age"
assert_contains "$SKILL" "frontmatter topics"
assert_contains "$SKILL" "existing wiki links"
assert_contains "$SKILL" "backlinks"
assert_contains "$SKILL" "MOCs/topic maps"
assert_contains "$SKILL" '`rg`'
assert_contains "$SKILL" "wiki-link and MOC/topic-map traversal"
assert_contains "$SKILL" "newer related notes"
assert_contains "$SKILL" "If I wrote this note today"
assert_contains "$SKILL" "backward links"
assert_contains "$SKILL" "claim sharpening"
assert_contains "$SKILL" "description improvement"
assert_contains "$SKILL" "split candidates"
assert_contains "$SKILL" "contradiction signals"
assert_contains "$SKILL" "tension signals"
assert_contains "$SKILL" "Default to report-only proposals"
assert_contains "$SKILL" "explicitly asks to edit immediately"
assert_contains "$SKILL" "focused inline wiki-link edits"
assert_contains "$SKILL" 'contextual `relevant_notes` entries'
assert_contains "$SKILL" "description improvements"
assert_contains "$SKILL" "small prose edits"
assert_contains "$SKILL" "Require separate approval before substantial rewrites, splits, or claim changes"
assert_contains "$SKILL" "Preserve existing note voice"
assert_contains "$SKILL" "avoid broad churn"
assert_contains "$SKILL" "hippocampusmd-validate"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" "Ralph handoff"
assert_contains "$SKILL" 'Do not create `ops/observations/` or `ops/tensions/` side-effect files'
assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/reweave"

printf 'PASS: reweave skill checks\n'
