#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-ralph/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-ralph"
assert_contains "$SKILL" "Use when the user asks Codex to inspect or process"
assert_contains "$SKILL" "standalone"
assert_contains "$SKILL" "arscontexta-pipeline"
assert_contains "$SKILL" "dry-run"
assert_contains "$SKILL" "report-only planning"
assert_contains "$SKILL" "before processing"
assert_contains "$SKILL" 'ops/queue/'
assert_contains "$SKILL" "no hidden background work"
assert_contains "$SKILL" "no inline task execution"
assert_contains "$SKILL" "Codex subagent rules"
assert_contains "$SKILL" "one bounded phase per spawned worker"
assert_contains "$SKILL" "parallel mode only when the user explicitly asks"
assert_contains "$SKILL" "scripts/ralph-vault.sh"
assert_contains "$SKILL" "plugins/arscontexta/scripts/ralph-vault.sh"
assert_contains "$SKILL" "deterministic queue inspection"
assert_contains "$SKILL" "queue-state mutation"
assert_contains "$SKILL" "arscontexta-seed"
assert_contains "$SKILL" "arscontexta-reduce"
assert_contains "$SKILL" "arscontexta-reflect"
assert_contains "$SKILL" "arscontexta-reweave"
assert_contains "$SKILL" "arscontexta-verify"
assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"

printf 'PASS: ralph skill checks\n'
