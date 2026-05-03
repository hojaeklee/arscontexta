#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
PLUGIN_CHECK="$PROJECT_ROOT/scripts/check-codex-plugin.sh"
VAULT_CHECK="$PROJECT_ROOT/scripts/check-vault.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq "$needle" || fail "expected output to contain: $needle"
}

assert_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >/tmp/arscontexta-test-out.$$ 2>&1
  local actual=$?
  output="$(cat /tmp/arscontexta-test-out.$$)"
  rm -f /tmp/arscontexta-test-out.$$
  set -e
  [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected but got $actual from $*; output: $output"
  printf '%s' "$output"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-codex-smoke-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

plugin_output="$(CODEX_CACHE_ROOT="$tmp_dir/cache" "$PLUGIN_CHECK")"
assert_contains "$plugin_output" "PASS .agents/plugins/marketplace.json parses."
assert_contains "$plugin_output" "PASS Plugin manifest uses skills path ./skills/."
assert_contains "$plugin_output" "PASS arscontexta-help skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-health skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-setup skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-session skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-validate skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-tasks skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-next skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-stats skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-graph skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-ask skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-recommend skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-reduce skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-reflect skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-reweave skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-verify skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-remember skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-rethink skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-architect skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-refactor skill exists in installable plugin."
assert_contains "$plugin_output" "PASS arscontexta-reseed skill exists in installable plugin."
assert_contains "$plugin_output" "PASS Bundled session orientation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled session validation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled session capture helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled MCP vault tools prototype helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault validation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault tasks helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault next action helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault stats helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault graph helper exists and is executable."

bad_config="$tmp_dir/bad-config.toml"
cat > "$bad_config" <<EOF
model = "gpt-5-codex"

[marketplaces.agenticnotetaking]
source_type = "local"
source = "$PROJECT_ROOT"

[plugins."arscontexta@agenticnotetaking"]
enabled = true
EOF

deny_output="$(assert_exit 1 env CODEX_CONFIG_PATH="$bad_config" CODEX_CACHE_ROOT="$tmp_dir/cache" "$PLUGIN_CHECK")"
assert_contains "$deny_output" "FAIL Codex config uses unsupported ChatGPT-account model gpt-5-codex."

vault="$tmp_dir/valid-vault"
mkdir -p "$vault/notes" "$vault/inbox" "$vault/ops" "$vault/self" "$vault/manual"
touch "$vault/.arscontexta"
cat > "$vault/notes/Index.md" <<'EOF'
---
description: Index
topics: []
---
Index.
EOF
touch "$vault/ops/derivation-manifest.md" "$vault/ops/derivation.md" "$vault/ops/config.yaml"

valid_output="$("$VAULT_CHECK" "$vault")"
assert_contains "$valid_output" "PASS .arscontexta marker exists."
assert_contains "$valid_output" "PASS Bounded vault health helper completed with parseable JSON."

missing_marker="$tmp_dir/missing-marker"
mkdir -p "$missing_marker/notes"
missing_output="$(assert_exit 1 "$VAULT_CHECK" "$missing_marker")"
assert_contains "$missing_output" "FAIL .arscontexta marker is missing."

generic="$tmp_dir/generic-markdown"
mkdir -p "$generic"
cat > "$generic/note.md" <<'EOF'
# Generic note
EOF
generic_output="$(assert_exit 1 "$VAULT_CHECK" "$generic")"
assert_contains "$generic_output" "FAIL .arscontexta marker is missing."

printf 'PASS: codex compatibility smoke tests\n'
