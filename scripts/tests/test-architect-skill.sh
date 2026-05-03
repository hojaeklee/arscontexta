#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-architect/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-architect"
assert_contains "$SKILL" "Use when the user asks Codex to review or evolve an existing Ars Contexta vault architecture"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "design intent"
assert_contains "$SKILL" "health reports"
assert_contains "$SKILL" "observations"
assert_contains "$SKILL" "tensions"
assert_contains "$SKILL" "methodology notes"
assert_contains "$SKILL" "recent sessions"
assert_contains "$SKILL" "goals"
assert_contains "$SKILL" "templates"
assert_contains "$SKILL" "queue state"
assert_contains "$SKILL" "graph signals"
assert_contains "$SKILL" "full-system review"
assert_contains "$SKILL" "focused-area review"
assert_contains "$SKILL" "dry-run"
assert_contains "$SKILL" "report-only"
assert_contains "$SKILL" "dimension-claim-map.md"
assert_contains "$SKILL" "interaction-constraints.md"
assert_contains "$SKILL" "methodology.md"
assert_contains "$SKILL" "failure-modes.md"
assert_contains "$SKILL" "tradition-presets.md"
assert_contains "$SKILL" "three-spaces.md"
assert_contains "$SKILL" "evolution-lifecycle.md"
assert_contains "$SKILL" "QMD"
assert_contains "$SKILL" "semantic search"
assert_contains "$SKILL" "3-5 ranked recommendations"
assert_contains "$SKILL" "evidence"
assert_contains "$SKILL" "research grounding"
assert_contains "$SKILL" "risk"
assert_contains "$SKILL" "reversibility"
assert_contains "$SKILL" "estimated effort"
assert_contains "$SKILL" "next step"
assert_contains "$SKILL" "cite local vault evidence"
assert_contains "$SKILL" "cite local reference paths"
assert_contains "$SKILL" "Do not auto-implement architecture changes"
assert_contains "$SKILL" "arscontexta-refactor"
assert_contains "$SKILL" "arscontexta-reseed"
assert_contains "$SKILL" "separate explicit follow-up"
assert_contains "$SKILL" "arscontexta-recommend"
assert_contains "$SKILL" "Do not assume Claude slash-command invocation"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/architect"

printf 'PASS: architect skill checks\n'
