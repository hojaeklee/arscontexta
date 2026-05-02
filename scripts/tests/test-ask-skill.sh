#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-ask/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-ask"
assert_contains "$SKILL" "Use when the user asks Codex questions about Ars Contexta methodology"
assert_contains "$SKILL" "read-only"
assert_contains "$SKILL" "rg"
assert_contains "$SKILL" "read local files before using optional semantic tooling"
assert_contains "$SKILL" "reference/"
assert_contains "$SKILL" "methodology/"
assert_contains "$SKILL" "README.md"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/methodology/"
assert_contains "$SKILL" "manual/"
assert_contains "$SKILL" "self/"
assert_contains "$SKILL" "Cite local paths when useful"
assert_contains "$SKILL" "Note gaps honestly"
assert_contains "$SKILL" "why"
assert_contains "$SKILL" "how"
assert_contains "$SKILL" "what"
assert_contains "$SKILL" "compare"
assert_contains "$SKILL" "diagnose"
assert_contains "$SKILL" "configure"
assert_contains "$SKILL" "evolve"
assert_contains "$SKILL" "Never require them"
assert_contains "$SKILL" "never present Claude slash-command tools as Codex requirements"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/ask"

printf 'PASS: ask skill checks\n'
