#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-reduce/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-reduce"
assert_contains "$SKILL" "Use when the user asks Codex to extract durable HippocampusMD notes"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "notes folder"
assert_contains "$SKILL" "inbox folder"
assert_contains "$SKILL" "explicit source file paths"
assert_contains "$SKILL" "inbox processing requests"
assert_contains "$SKILL" "pasted source material"
assert_contains "$SKILL" "Read the source fully"
assert_contains "$SKILL" "large sources"
assert_contains "$SKILL" "extraction report before note creation"
assert_contains "$SKILL" "explicitly asked to write notes immediately"
assert_contains "$SKILL" "Write only under the configured notes folder"
assert_contains "$SKILL" "valid YAML frontmatter"
assert_contains "$SKILL" "stable wiki links"
assert_contains "$SKILL" "local templates"
assert_contains "$SKILL" "_schema"
assert_contains "$SKILL" "description"
assert_contains "$SKILL" "topics"
assert_contains "$SKILL" "hippocampusmd-validate"
assert_contains "$SKILL" 'Do not automatically mutate `ops/queue/*`'
assert_contains "$SKILL" 'Do not create `ops/observations/` or `ops/tensions/` side-effect files'
assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/reduce"

printf 'PASS: reduce skill checks\n'
