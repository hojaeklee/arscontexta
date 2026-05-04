#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/hippocampusmd/skills/hippocampusmd-learn/SKILL.md"

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
assert_contains "$SKILL" "name: hippocampusmd-learn"
assert_contains "$SKILL" "Use when the user asks Codex to research a topic"
assert_contains "$SKILL" "current directory as the vault"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "If the user provides a topic"
assert_contains "$SKILL" "If no topic is provided"
assert_contains "$SKILL" "self/goals.md"
assert_contains "$SKILL" "Web/network research is optional"
assert_contains "$SKILL" "explicit confirmation before web/network research"
assert_contains "$SKILL" "offline path"
assert_contains "$SKILL" "user-provided research text"
assert_contains "$SKILL" "local files"
assert_contains "$SKILL" "Create research capture files only after confirmation"
assert_contains "$SKILL" "configured inbox folder"
assert_contains "$SKILL" "Preserve existing vault content"
assert_contains "$SKILL" "valid YAML frontmatter"
assert_contains "$SKILL" "description"
assert_contains "$SKILL" "source_type"
assert_contains "$SKILL" "research_prompt"
assert_contains "$SKILL" "generated"
assert_contains "$SKILL" "domain"
assert_contains "$SKILL" "topics"
assert_contains "$SKILL" "Clear source boundaries"
assert_contains "$SKILL" "web results"
assert_contains "$SKILL" "local file excerpts"
assert_contains "$SKILL" "user-provided material"
assert_contains "$SKILL" "synthesized findings"
assert_contains "$SKILL" "No fabricated sources or URLs"
assert_contains "$SKILL" "## Key Findings"
assert_contains "$SKILL" "## Sources"
assert_contains "$SKILL" "## Research Directions"
assert_contains "$SKILL" "hippocampusmd-seed"
assert_contains "$SKILL" "hippocampusmd-pipeline"
assert_contains "$SKILL" "Do not process research directly"
assert_contains "$SKILL" "Do not start downstream processing automatically"
assert_contains "$SKILL" "Codex conversation"
assert_contains "$SKILL" "No deterministic helper script"
assert_not_contains "$SKILL" "AskUserQuestion"
assert_not_contains "$SKILL" "allowed-tools"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "Exa"
assert_not_contains "$SKILL" "slash-command"
assert_not_contains "$SKILL" '"/learn"'
assert_not_contains "$SKILL" '`/learn'
assert_not_contains "$SKILL" '`/reduce'

printf 'PASS: learn skill checks\n'
