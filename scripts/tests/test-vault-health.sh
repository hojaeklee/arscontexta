#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
HEALTH_SCRIPT="$PROJECT_ROOT/scripts/vault-health.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq "$needle" || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "did not expect output to contain: $needle"
  fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-health-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes" "$vault/templates" "$vault/reference" "$vault/ops/health"
touch "$vault/.arscontexta"

printf '%s\n' \
  '---' \
  'description: Source note' \
  'topics: [[Index]]' \
  '---' \
  'Links to [[Target]], [[Target|the target]], [[Target#Heading]], and [[Missing Primary]].' \
  > "$vault/notes/Source.md"

printf '%s\n' \
  '---' \
  'description: Target note' \
  'topics: [[Index]]' \
  '---' \
  'A valid target.' \
  > "$vault/notes/Target.md"

printf '%s\n' \
  '---' \
  'description: Index' \
  'topics: []' \
  '---' \
  'Index note.' \
  > "$vault/notes/Index.md"

printf '%s\n' \
  'Examples: [[Template Missing 1]] [[Template Missing 2]] [[Template Missing 3]] [[Template Missing 4]]' \
  > "$vault/templates/example.md"

printf '%s\n' \
  'Historical report links to [[Operational Missing]].' \
  > "$vault/ops/health/report.md"

output="$("$HEALTH_SCRIPT" "$vault" --mode quick --limit 2 --format text)"
assert_contains "$output" "Overall: FAIL"
assert_contains "$output" "Primary: 1"
assert_contains "$output" "Operational: 1"
assert_contains "$output" "Noise/docs/templates: 4"
assert_contains "$output" "[[Missing Primary]]"
assert_not_contains "$output" "[[Target|"
assert_not_contains "$output" "[[Target#"
assert_contains "$output" "... 2 more omitted by --limit 2"

noise_vault="$tmp_dir/noise-vault"
mkdir -p "$noise_vault/notes" "$noise_vault/templates"
printf '%s\n' \
  '---' \
  'description: Clean note' \
  'topics: []' \
  '---' \
  'No broken primary links.' \
  > "$noise_vault/notes/Clean.md"
printf '%s\n' 'Example [[Missing Example]].' > "$noise_vault/templates/template.md"

noise_output="$("$HEALTH_SCRIPT" "$noise_vault" --mode quick --limit 1 --format text)"
assert_contains "$noise_output" "Overall: PASS"
assert_contains "$noise_output" ".arscontexta was not detected"
assert_contains "$noise_output" "Noise/docs/templates: 1"

json_output="$("$HEALTH_SCRIPT" "$vault" --mode quick --limit 2 --format json)"
assert_contains "$json_output" '"overall": "FAIL"'
assert_contains "$json_output" '"primary": 1'

printf 'PASS: vault-health bounded checks\n'
