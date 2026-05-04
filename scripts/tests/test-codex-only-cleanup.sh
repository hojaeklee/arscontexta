#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_absent() {
  [[ ! -e "$PROJECT_ROOT/$1" ]] || fail "expected legacy path to be absent: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$PROJECT_ROOT/$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$PROJECT_ROOT/$file"; then
    fail "expected $file not to contain: $needle"
  fi
}

for legacy_path in \
  ".claude" \
  ".claude-plugin" \
  "hooks" \
  "platforms/claude-code" \
  "platforms/shared/skill-blocks" \
  "skills" \
  "skill-sources" \
  "agents" \
  "generators" \
  "presets"
do
  assert_absent "$legacy_path"
done

assert_contains "README.md" "Codex is the only supported HippocampusMD distribution in this repo."
assert_contains "README.md" 'plugins/hippocampusmd/ is the source of truth'
assert_contains "README.md" "Claude Code support, hooks, slash commands, and legacy generated skill templates have been removed."

for stale in \
  "legacy Claude plugin available" \
  "Legacy Claude Commands" \
  "Port Claude" \
  "full Claude setup parity" \
  "skill-sources/" \
  "Legacy Claude-oriented skills"
do
  assert_not_contains "README.md" "$stale"
done

if rg -n -g '!**/test-codex-only-cleanup.sh' \
  "skill-sources/|root skills/|CLAUDE_PLUGIN_ROOT|claude_hooks|full Claude setup parity" \
  "$PROJECT_ROOT/plugins" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/platforms" >/tmp/hippocampusmd-cleanup-rg.$$ 2>/dev/null; then
  cat /tmp/hippocampusmd-cleanup-rg.$$ >&2
  rm -f /tmp/hippocampusmd-cleanup-rg.$$
  fail "active Codex surfaces still reference legacy Claude/template sources"
fi
rm -f /tmp/hippocampusmd-cleanup-rg.$$

printf 'PASS: codex-only cleanup checks\n'
