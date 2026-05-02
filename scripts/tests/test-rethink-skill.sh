#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-rethink/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-rethink"
assert_contains "$SKILL" "Use when the user asks Codex to review accumulated Ars Contexta observations"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "thresholds"
assert_contains "$SKILL" 'ops/methodology/'
assert_contains "$SKILL" 'ops/observations/'
assert_contains "$SKILL" 'ops/tensions/'
assert_contains "$SKILL" "full review"
assert_contains "$SKILL" '`triage`'
assert_contains "$SKILL" '`patterns`'
assert_contains "$SKILL" '`drift`'
assert_contains "$SKILL" "single-file evidence review"
assert_contains "$SKILL" "promote"
assert_contains "$SKILL" "methodology update"
assert_contains "$SKILL" "implementation proposal"
assert_contains "$SKILL" "archive or dissolve"
assert_contains "$SKILL" "keep pending"
assert_contains "$SKILL" "Do not fabricate patterns"
assert_contains "$SKILL" "three or more"
assert_contains "$SKILL" "cite local evidence paths"
assert_contains "$SKILL" "proposal-only report"
assert_contains "$SKILL" "explicit user approval before any file write"
assert_contains "$SKILL" "note, methodology, config, context, changelog, or status edits"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" "pipeline state"
assert_contains "$SKILL" "arscontexta-architect"
assert_contains "$SKILL" "arscontexta-refactor"
assert_contains "$SKILL" "arscontexta-reseed"
assert_contains "$SKILL" "Do not assume Claude slash-command invocation"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/rethink"

printf 'PASS: rethink skill checks\n'
