#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-recommend/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-recommend"
assert_contains "$SKILL" "Use when the user asks Codex for Ars Contexta architecture advice"
assert_contains "$SKILL" "advisory and read-only"
assert_contains "$SKILL" "rg"
assert_contains "$SKILL" "read local files before using optional semantic tooling"
assert_contains "$SKILL" "reference/"
assert_contains "$SKILL" "methodology/"
assert_contains "$SKILL" "reference/tradition-presets.md"
assert_contains "$SKILL" "reference/methodology.md"
assert_contains "$SKILL" "reference/components.md"
assert_contains "$SKILL" "reference/dimension-claim-map.md"
assert_contains "$SKILL" "reference/interaction-constraints.md"
assert_contains "$SKILL" "reference/claim-map.md"
assert_contains "$SKILL" "ask at most 1-2 clarifying questions"
assert_contains "$SKILL" "domain, goals, pain points"
assert_contains "$SKILL" "operator"
assert_contains "$SKILL" "expected scale"
assert_contains "$SKILL" "closest preset"
assert_contains "$SKILL" "granularity, organization, linking, processing, navigation, maintenance, schema, and automation"
assert_contains "$SKILL" "citations to local reference or methodology paths"
assert_contains "$SKILL" "Do not generate a vault"
assert_contains "$SKILL" "Do not apply architecture changes"
assert_contains "$SKILL" "Never require them"
assert_contains "$SKILL" "never present Claude slash-command tools as Codex requirements"
assert_contains "$SKILL" "Use Codex skill language"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/recommend"

printf 'PASS: recommend skill checks\n'
