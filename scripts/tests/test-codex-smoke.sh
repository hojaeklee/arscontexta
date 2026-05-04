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
  "$@" >/tmp/hippocampusmd-test-out.$$ 2>&1
  local actual=$?
  output="$(cat /tmp/hippocampusmd-test-out.$$)"
  rm -f /tmp/hippocampusmd-test-out.$$
  set -e
  [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected but got $actual from $*; output: $output"
  printf '%s' "$output"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-codex-smoke-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

plugin_output="$(CODEX_CACHE_ROOT="$tmp_dir/cache" "$PLUGIN_CHECK")"
assert_contains "$plugin_output" "PASS .agents/plugins/marketplace.json parses."
assert_contains "$plugin_output" "PASS Plugin manifest uses skills path ./skills/."
assert_contains "$plugin_output" "PASS hippocampusmd-help skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-health skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-setup skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-session skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-validate skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-tasks skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-next skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-index skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-stats skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-graph skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-ask skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-recommend skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-reduce skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-reflect skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-reweave skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-verify skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-remember skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-rethink skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-architect skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-refactor skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-reseed skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-upgrade skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-add-domain skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-seed skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-ralph skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-pipeline skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-archive-batch skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-tutorial skill exists in installable plugin."
assert_contains "$plugin_output" "PASS hippocampusmd-learn skill exists in installable plugin."
assert_contains "$plugin_output" "PASS Bundled session orientation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled session validation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled session capture helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled MCP vault tools prototype helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault validation helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault tasks helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault next action helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault stats helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault graph helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault seed helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault ralph helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault pipeline helper exists and is executable."
assert_contains "$plugin_output" "PASS Bundled vault archive-batch helper exists and is executable."

bad_config="$tmp_dir/bad-config.toml"
cat > "$bad_config" <<EOF
model = "gpt-5-codex"

[marketplaces.hippocampusmd]
source_type = "local"
source = "$PROJECT_ROOT"

[plugins."hippocampusmd@hippocampusmd"]
enabled = true
EOF

deny_output="$(assert_exit 1 env CODEX_CONFIG_PATH="$bad_config" CODEX_CACHE_ROOT="$tmp_dir/cache" "$PLUGIN_CHECK")"
assert_contains "$deny_output" "FAIL Codex config uses unsupported ChatGPT-account model gpt-5-codex."

vault="$tmp_dir/valid-vault"
mkdir -p "$vault/notes" "$vault/inbox" "$vault/ops" "$vault/self" "$vault/manual"
touch "$vault/.hippocampusmd"
cat > "$vault/notes/Index.md" <<'EOF'
---
description: Index
topics: []
---
Index.
EOF
touch "$vault/ops/derivation-manifest.md" "$vault/ops/derivation.md" "$vault/ops/config.yaml"

valid_output="$("$VAULT_CHECK" "$vault")"
assert_contains "$valid_output" "PASS .hippocampusmd marker exists."
assert_contains "$valid_output" "PASS Bounded vault health helper completed with parseable JSON."

missing_marker="$tmp_dir/missing-marker"
mkdir -p "$missing_marker/notes"
missing_output="$(assert_exit 1 "$VAULT_CHECK" "$missing_marker")"
assert_contains "$missing_output" "FAIL .hippocampusmd marker is missing."

generic="$tmp_dir/generic-markdown"
mkdir -p "$generic"
cat > "$generic/note.md" <<'EOF'
# Generic note
EOF
generic_output="$(assert_exit 1 "$VAULT_CHECK" "$generic")"
assert_contains "$generic_output" "FAIL .hippocampusmd marker is missing."

printf 'PASS: codex compatibility smoke tests\n'
