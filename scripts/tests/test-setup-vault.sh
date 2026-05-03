#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SETUP_SCRIPT="$PROJECT_ROOT/plugins/arscontexta/scripts/setup-vault.sh"
CHECK_VAULT="$PROJECT_ROOT/scripts/check-vault.sh"
HEALTH_SCRIPT="$PROJECT_ROOT/plugins/arscontexta/scripts/vault-health.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_no_dir() {
  [[ ! -d "$1" ]] || fail "did not expect directory: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "did not expect $file to contain: $needle"
  fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-setup-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

for preset in research personal experimental; do
  vault="$tmp_dir/$preset-vault"
  "$SETUP_SCRIPT" "$vault" --preset "$preset" --domain "$preset domain" >/dev/null

  assert_file "$vault/.arscontexta"
  assert_file "$vault/AGENTS.md"
  assert_file "$vault/ops/derivation.md"
  assert_file "$vault/ops/derivation-manifest.md"
  assert_file "$vault/ops/config.yaml"
  assert_file "$vault/templates/base-note.md"
  assert_file "$vault/templates/moc.md"
  assert_file "$vault/manual/manual.md"
  assert_file "$vault/manual/getting-started.md"
  assert_file "$vault/manual/skills.md"
  assert_file "$vault/notes/index.md"
  assert_dir "$vault/ops/queue"
  assert_dir "$vault/ops/health"
  assert_dir "$vault/ops/observations"
  assert_dir "$vault/ops/tensions"
  assert_dir "$vault/ops/sessions"
  assert_dir "$vault/ops/methodology"
  assert_no_dir "$vault/methodology"
  assert_no_dir "$vault/reference"
  assert_no_dir "$vault/generators"
  assert_no_dir "$vault/presets"

  assert_contains "$vault/AGENTS.md" "Codex-oriented Ars Contexta vault"
  assert_contains "$vault/AGENTS.md" "explicit session workflows"
  assert_contains "$vault/AGENTS.md" "no hidden background automation"
  assert_contains "$vault/ops/config.yaml" "vocabulary:"
  assert_contains "$vault/ops/config.yaml" "extraction_categories:"
  assert_contains "$vault/ops/config.yaml" "scan:"
  assert_contains "$vault/ops/config.yaml" "  include:"
  assert_contains "$vault/ops/config.yaml" "  exclude:"
  assert_contains "$vault/ops/config.yaml" "    - notes/**"
  assert_contains "$vault/ops/config.yaml" "    - ops/cache/**"

  "$CHECK_VAULT" "$vault" >/dev/null
  "$HEALTH_SCRIPT" "$vault" --mode quick --limit 5 --format json >/dev/null
done

assert_file "$tmp_dir/research-vault/notes/methods.md"
assert_file "$tmp_dir/research-vault/notes/open-questions.md"
assert_file "$tmp_dir/personal-vault/notes/life-areas.md"
assert_file "$tmp_dir/personal-vault/notes/people.md"
assert_file "$tmp_dir/personal-vault/notes/goals.md"
assert_contains "$tmp_dir/research-vault/ops/config.yaml" "  note: claim"
assert_contains "$tmp_dir/research-vault/ops/config.yaml" "  - claims"
assert_contains "$tmp_dir/personal-vault/ops/config.yaml" "  note: reflection"
assert_contains "$tmp_dir/personal-vault/ops/config.yaml" "  - reflections"
assert_contains "$tmp_dir/experimental-vault/ops/config.yaml" "extraction_categories: []"

dry_vault="$tmp_dir/dry-run-vault"
"$SETUP_SCRIPT" "$dry_vault" --preset research --domain "dry run" --dry-run >/dev/null
[[ ! -e "$dry_vault" ]] || fail "dry-run should not create target directory"

idempotent="$tmp_dir/idempotent-vault"
"$SETUP_SCRIPT" "$idempotent" --preset research --domain "idempotent" >/dev/null
before="$(find "$idempotent" -type f -print | sort | xargs shasum)"
"$SETUP_SCRIPT" "$idempotent" --preset research --domain "idempotent" >/dev/null
after="$(find "$idempotent" -type f -print | sort | xargs shasum)"
[[ "$before" == "$after" ]] || fail "second setup run changed existing files"

existing="$tmp_dir/existing-markdown"
mkdir -p "$existing"
printf '# Existing note\n' > "$existing/old.md"
old_hash="$(shasum "$existing/old.md")"
"$SETUP_SCRIPT" "$existing" --preset experimental --domain "existing notes" >/dev/null
new_hash="$(shasum "$existing/old.md")"
[[ "$old_hash" == "$new_hash" ]] || fail "existing markdown file changed"
assert_file "$existing/.arscontexta"
assert_file "$existing/AGENTS.md"

printf 'PASS: setup vault fixtures\n'
