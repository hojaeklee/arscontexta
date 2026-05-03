#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-seed/SKILL.md"

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
assert_contains "$SKILL" "name: arscontexta-seed"
assert_contains "$SKILL" "Use when the user asks Codex to add a source file"
assert_contains "$SKILL" "scripts/seed-vault.sh"
assert_contains "$SKILL" "plugins/arscontexta/scripts/seed-vault.sh"
assert_contains "$SKILL" "ops/derivation-manifest.md"
assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "inbox"
assert_contains "$SKILL" "ops/queue/"
assert_contains "$SKILL" "ops/queue/archive/"
assert_contains "$SKILL" "duplicate"
assert_contains "$SKILL" "avoid duplicates"
assert_contains "$SKILL" 'queue state stays under `ops/queue/`'
assert_contains "$SKILL" "Move sources only when they are inside the configured inbox"
assert_contains "$SKILL" "Living docs outside inbox stay in place"
assert_contains "$SKILL" "File moves and archive writes must be clearly reported"
assert_contains "$SKILL" "avoid overwriting user content"
assert_contains "$SKILL" "next_claim_start"
assert_contains "$SKILL" "extract task"
assert_contains "$SKILL" "arscontexta-ralph"
assert_contains "$SKILL" "arscontexta-pipeline"
assert_contains "$SKILL" "Do not assume Claude slash-command invocation"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"

printf 'PASS: seed skill checks\n'
