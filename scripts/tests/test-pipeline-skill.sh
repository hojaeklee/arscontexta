#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-pipeline/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-pipeline"
assert_contains "$SKILL" "Use when the user asks Codex to process one local source"
assert_contains "$SKILL" "arscontexta-seed"
assert_contains "$SKILL" "arscontexta-ralph"
assert_contains "$SKILL" "arscontexta-reduce"
assert_contains "$SKILL" "arscontexta-reflect"
assert_contains "$SKILL" "arscontexta-reweave"
assert_contains "$SKILL" "arscontexta-verify"
assert_contains "$SKILL" "plan/status before processing"
assert_contains "$SKILL" "Codex subagent constraints"
assert_contains "$SKILL" "hidden background work"
assert_contains "$SKILL" "failure reporting"
assert_contains "$SKILL" "resumability"
assert_contains "$SKILL" "arscontexta-archive-batch"
assert_contains "$SKILL" "ops/queue/"
assert_contains "$SKILL" "scripts/pipeline-vault.sh"
assert_contains "$SKILL" "plugins/arscontexta/scripts/pipeline-vault.sh"
assert_contains "$SKILL" "orchestration skill"
assert_contains "$SKILL" "not a new queue engine"
assert_contains "$SKILL" "Do not assume Claude slash-command invocation"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"

printf 'PASS: pipeline skill checks\n'
