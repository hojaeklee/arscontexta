#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-index/SKILL.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected skill to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "expected skill not to contain: $needle"
  fi
}

[[ -f "$SKILL" ]] || fail "missing arscontexta-index skill"

skill_text="$(cat "$SKILL")"
assert_contains "$skill_text" "name: arscontexta-index"
assert_contains "$skill_text" "vault-index.sh"
assert_contains "$skill_text" "build"
assert_contains "$skill_text" "status"
assert_contains "$skill_text" "export"
assert_contains "$skill_text" "ops/cache/index.sqlite"
assert_contains "$skill_text" "ops/cache/"
assert_not_contains "$skill_text" "vault_index.py"

printf 'PASS: index skill checks\n'
