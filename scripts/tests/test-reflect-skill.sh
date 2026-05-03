#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-reflect/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-reflect"
assert_contains "$SKILL" "Use when the user asks Codex to find meaningful connections"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "specific note"
assert_contains "$SKILL" "topic area or MOC/topic map"
assert_contains "$SKILL" '`recent` or `new` notes'
assert_contains "$SKILL" "user-selected set of notes"
assert_contains "$SKILL" "Read target notes fully"
assert_contains "$SKILL" "Use local search before optional semantic tooling"
assert_contains "$SKILL" "frontmatter topics"
assert_contains "$SKILL" "existing wiki links"
assert_contains "$SKILL" "backlinks"
assert_contains "$SKILL" "MOCs/topic maps"
assert_contains "$SKILL" '`rg`'
assert_contains "$SKILL" "wiki-link traversal"
assert_contains "$SKILL" "articulation test"
assert_contains "$SKILL" "[[note A]] connects to [[note B]] because"
assert_contains "$SKILL" "Produce a connection report before editing"
assert_contains "$SKILL" "explicitly asks to edit immediately"
assert_contains "$SKILL" "focused inline wiki links"
assert_contains "$SKILL" 'contextual `relevant_notes` entries'
assert_contains "$SKILL" "MOC/topic-map additions"
assert_contains "$SKILL" "Preserve existing note voice"
assert_contains "$SKILL" "arscontexta-validate"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" "Ralph handoff"
assert_contains "$SKILL" 'Do not create `ops/observations/` or `ops/tensions/` side-effect files'
assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/reflect"

printf 'PASS: reflect skill checks\n'
