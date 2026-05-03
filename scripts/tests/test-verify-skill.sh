#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-verify/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-verify"
assert_contains "$SKILL" "Use when the user asks Codex to verify Ars Contexta note quality"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "specific note"
assert_contains "$SKILL" '`recent` notes'
assert_contains "$SKILL" "small changed set"
assert_contains "$SKILL" "Do not dump noisy whole-vault output"
assert_contains "$SKILL" "validate-vault.sh"
assert_contains "$SKILL" "schema/frontmatter"
assert_contains "$SKILL" "description"
assert_contains "$SKILL" "wiki-link"
assert_contains "$SKILL" "topic-map/MOC integration"
assert_contains "$SKILL" "sparse/orphan risk"
assert_contains "$SKILL" "bounded graph/health helpers"
assert_contains "$SKILL" '`rg`'
assert_contains "$SKILL" "wiki-link traversal"
assert_contains "$SKILL" "backlinks"
assert_contains "$SKILL" "optional semantic tooling"
assert_contains "$SKILL" 'Report `PASS`, `WARN`, and `FAIL` findings'
assert_contains "$SKILL" "adds information beyond the title"
assert_contains "$SKILL" "YAML validity"
assert_contains "$SKILL" "required fields"
assert_contains "$SKILL" "enum values"
assert_contains "$SKILL" '`description`/`topics` defaults'
assert_contains "$SKILL" 'body links, topics, and `relevant_notes`'
assert_contains "$SKILL" "arscontexta-reflect"
assert_contains "$SKILL" "arscontexta-reweave"
assert_contains "$SKILL" "arscontexta-validate"
assert_contains "$SKILL" "Do not edit notes by default"
assert_contains "$SKILL" "Do not automatically edit notes"
assert_contains "$SKILL" 'mutate `ops/queue/*`'
assert_contains "$SKILL" "Ralph handoff"
assert_contains "$SKILL" 'Do not create `ops/observations/` or `ops/tensions/` side-effect files'
assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__qmd__"
assert_not_contains "$SKILL" "/verify"

printf 'PASS: verify skill checks\n'
