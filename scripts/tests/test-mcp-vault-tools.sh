#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
TOOL="$PROJECT_ROOT/scripts/mcp-vault-tools.sh"
PLUGIN_TOOL="$PROJECT_ROOT/plugins/arscontexta/scripts/mcp-vault-tools.sh"

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
  "$@" >/tmp/arscontexta-mcp-test-out.$$ 2>&1
  local actual=$?
  output="$(cat /tmp/arscontexta-mcp-test-out.$$)"
  rm -f /tmp/arscontexta-mcp-test-out.$$
  set -e
  [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected but got $actual from $*; output: $output"
  printf '%s' "$output"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-mcp-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes" "$vault/ops/queue"
touch "$vault/.arscontexta"
cat > "$vault/notes/index.md" <<'EOF'
---
description: Entry point
topics: []
---

# index
EOF
cat > "$vault/notes/valid.md" <<'EOF'
---
description: Valid note
topics:
- [[index]]
---

# valid

Links to [[index]] and [[missing target]].
EOF
cat > "$vault/notes/invalid.md" <<'EOF'
# invalid

Links to [[missing target]].
EOF

links_output="$("$TOOL" links.check "$vault" --limit 5)"
assert_contains "$links_output" '"tool": "arscontexta.links.check"'
assert_contains "$links_output" '"overall": "FAIL"'
assert_contains "$links_output" '"broken_total": 2'
assert_contains "$links_output" '"target":"missing target"'

valid_output="$("$TOOL" frontmatter.validate "$vault" --file notes/index.md --limit 5)"
assert_contains "$valid_output" '"tool": "arscontexta.frontmatter.validate"'
assert_contains "$valid_output" '"overall": "PASS"'
assert_contains "$valid_output" '"warnings": 0'

invalid_output="$("$TOOL" frontmatter.validate "$vault" --file notes/invalid.md --limit 5)"
assert_contains "$invalid_output" '"overall": "WARN"'
assert_contains "$invalid_output" 'Missing YAML frontmatter'
assert_contains "$invalid_output" 'Missing non-empty description'
assert_contains "$invalid_output" 'Missing topics'
assert_contains "$invalid_output" '"target":"missing target"'

git_vault="$tmp_dir/git-vault"
cp -R "$vault" "$git_vault"
git -C "$git_vault" init --quiet
git -C "$git_vault" config user.email "test@example.com"
git -C "$git_vault" config user.name "Ars Contexta Test"
git -C "$git_vault" add .
git -C "$git_vault" commit --quiet -m "test: seed vault"
cat > "$git_vault/notes/changed.md" <<'EOF'
# changed
EOF
changed_output="$("$TOOL" frontmatter.validate "$git_vault" --changed --limit 5)"
assert_contains "$changed_output" '"files_checked": 1'
assert_contains "$changed_output" '"file":"notes/changed.md"'

usage_output="$(assert_exit 2 "$TOOL" frontmatter.validate "$vault" --file notes/index.md --changed)"
assert_contains "$usage_output" "Use only one of --file, --changed, or --all."

diff -u "$TOOL" "$PLUGIN_TOOL" >/dev/null || fail "root and plugin mcp-vault-tools.sh differ"

printf 'PASS: MCP vault tools tests\n'
