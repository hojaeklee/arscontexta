#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-remember/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-remember"
assert_contains "$SKILL" "Use when the user asks Codex to capture Ars Contexta learnings"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" 'ops/methodology/'
assert_contains "$SKILL" 'ops/observations/'
assert_contains "$SKILL" 'ops/tensions/'
assert_contains "$SKILL" "explicit mode"
assert_contains "$SKILL" "contextual mode"
assert_contains "$SKILL" "session-mining mode"
assert_contains "$SKILL" 'ops/sessions/'
assert_contains "$SKILL" "ask confirmation before writing"
assert_contains "$SKILL" 'Methodology notes go in `ops/methodology/`'
assert_contains "$SKILL" 'Observations go in `ops/observations/`'
assert_contains "$SKILL" 'Tensions go in `ops/tensions/`'
assert_contains "$SKILL" 'Update `ops/methodology.md` only'
assert_contains "$SKILL" "Explicit user-provided learnings may be written after confirming"
assert_contains "$SKILL" "Contextual and session-mined learnings require user confirmation"
assert_contains "$SKILL" "Prefer extending existing notes"
assert_contains "$SKILL" "meaningfully distinct"
assert_contains "$SKILL" "specific, scoped, and actionable"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" "Ralph handoff"
assert_contains "$SKILL" "pipeline task updates"
assert_contains "$SKILL" "defer broader adaptation to rethink, refactor, or later evolution workflows"
assert_contains "$SKILL" "Do not assume Claude slash-command invocation"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/remember"

printf 'PASS: remember skill checks\n'
