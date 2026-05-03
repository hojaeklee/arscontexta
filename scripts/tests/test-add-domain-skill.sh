#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$PROJECT_ROOT/plugins/arscontexta/skills/arscontexta-add-domain/SKILL.md"

assert_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "FAIL: expected file $file" >&2
        exit 1
    fi
}

assert_contains() {
    local file="$1"
    local expected="$2"
    if ! grep -Fq -- "$expected" "$file"; then
        echo "FAIL: expected $file to contain: $expected" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        echo "FAIL: expected $file not to contain: $unexpected" >&2
        exit 1
    fi
}

assert_file "$SKILL"
assert_contains "$SKILL" "name: arscontexta-add-domain"
assert_contains "$SKILL" "Use when the user asks Codex to add a new Ars Contexta knowledge domain"

assert_contains "$SKILL" "ops/derivation.md"
assert_contains "$SKILL" "ops/config.yaml"
assert_contains "$SKILL" "ops/derivation-manifest.md"

assert_contains "$SKILL" "existing domains"
assert_contains "$SKILL" "notes folders"
assert_contains "$SKILL" "templates"
assert_contains "$SKILL" "MOCs"
assert_contains "$SKILL" "vocabulary"
assert_contains "$SKILL" "schemas"
assert_contains "$SKILL" 'self/'
assert_contains "$SKILL" 'ops/'

assert_contains "$SKILL" "minimal Codex conversation"
assert_contains "$SKILL" "purpose"
assert_contains "$SKILL" "cross-domain relationship"
assert_contains "$SKILL" "volume"
assert_contains "$SKILL" "processing intensity"
assert_contains "$SKILL" "schema needs"
assert_contains "$SKILL" "linking patterns"

assert_contains "$SKILL" "system-level dimensions"
assert_contains "$SKILL" "domain-adjustable dimensions"

assert_contains "$SKILL" "derivation-validation.md"
assert_contains "$SKILL" "three-spaces.md"
assert_contains "$SKILL" "interaction-constraints.md"
assert_contains "$SKILL" "vocabulary-transforms.md"
assert_contains "$SKILL" "tradition-presets.md"
assert_contains "$SKILL" "use-case-presets.md"
assert_contains "$SKILL" "dimension-claim-map.md"
assert_contains "$SKILL" "failure-modes.md"

assert_contains "$SKILL" "filenames"
assert_contains "$SKILL" "folders"
assert_contains "$SKILL" "template names"
assert_contains "$SKILL" "schema fields"

assert_contains "$SKILL" "domain-addition proposal"
assert_contains "$SKILL" "confirmation before generation"

assert_contains "$SKILL" "domain MOC"
assert_contains "$SKILL" "hub MOC update"
assert_contains "$SKILL" "derivation update"
assert_contains "$SKILL" "preserve existing architecture"
assert_contains "$SKILL" "avoid replacing existing domain files"

assert_contains "$SKILL" "kernel checks"
assert_contains "$SKILL" "wiki links"
assert_contains "$SKILL" "hub reachability"
assert_contains "$SKILL" "filename uniqueness"
assert_contains "$SKILL" "schema conflicts"
assert_contains "$SKILL" "vocabulary isolation"

assert_contains "$SKILL" "Use Codex file workflows"
assert_contains "$SKILL" "Codex file workflows"
assert_not_contains "$SKILL" "mcp__"
assert_not_contains "$SKILL" "/add-domain"

printf 'PASS: add-domain skill checks\n'
