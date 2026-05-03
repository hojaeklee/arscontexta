#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-tutorial/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-tutorial"
assert_contains "$SKILL" "Use when the user asks Codex for an Ars Contexta tutorial"
assert_contains "$SKILL" "researcher"
assert_contains "$SKILL" "manager"
assert_contains "$SKILL" "personal"
assert_contains "$SKILL" "WHY / DO / SEE"
assert_contains "$SKILL" "capture"
assert_contains "$SKILL" "discover"
assert_contains "$SKILL" "process"
assert_contains "$SKILL" "maintain"
assert_contains "$SKILL" "reflect"
assert_contains "$SKILL" "report/planning mode before writes"
assert_contains "$SKILL" "Sample note creation requires explicit confirmation"
assert_contains "$SKILL" "ops/tutorial-state.yaml"
assert_contains "$SKILL" "resume"
assert_contains "$SKILL" "Reset requires explicit confirmation"
assert_contains "$SKILL" "Preserve existing vault content"
assert_contains "$SKILL" "write only approved tutorial notes under the configured notes folder"
assert_contains "$SKILL" "valid YAML frontmatter"
assert_contains "$SKILL" "description"
assert_contains "$SKILL" "topics"
assert_contains "$SKILL" "wiki links where genuine"
assert_contains "$SKILL" "no forced connections"
assert_contains "$SKILL" "arscontexta-validate"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "Codex conversation"
assert_contains "$SKILL" "current directory as the vault"
assert_contains "$SKILL" "arscontexta-reduce"
assert_contains "$SKILL" "arscontexta-reflect"
assert_contains "$SKILL" "arscontexta-graph"
assert_contains "$SKILL" "arscontexta-health"
assert_contains "$SKILL" "arscontexta-pipeline"
assert_contains "$SKILL" "arscontexta-learn"
assert_not_contains "$SKILL" "AskUserQuestion"
assert_not_contains "$SKILL" "allowed-tools"
assert_not_contains "$SKILL" "slash-command"
assert_not_contains "$SKILL" '"/tutorial"'
assert_not_contains "$SKILL" '`/learn'
assert_not_contains "$SKILL" '`/reduce'
assert_not_contains "$SKILL" '`/reflect'
assert_not_contains "$SKILL" "mcp__"

printf 'PASS: tutorial skill checks\n'
