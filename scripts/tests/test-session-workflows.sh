#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
ORIENT="$PROJECT_ROOT/scripts/session-orient.sh"
VALIDATE="$PROJECT_ROOT/scripts/session-validate.sh"
CAPTURE="$PROJECT_ROOT/scripts/session-capture.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq "$needle" || fail "expected output to contain: $needle"
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-session-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p \
  "$vault/notes" \
  "$vault/inbox" \
  "$vault/ops/queue" \
  "$vault/ops/observations" \
  "$vault/ops/tensions" \
  "$vault/ops/sessions" \
  "$vault/ops/health" \
  "$vault/self"

touch "$vault/.arscontexta"
cat > "$vault/self/goals.md" <<'EOF'
# Goals

- Continue the Codex migration.
EOF
cat > "$vault/ops/sessions/current.md" <<'EOF'
# Current handoff

Pick up with session workflow tests.
EOF
cat > "$vault/inbox/source.md" <<'EOF'
# Source
EOF
cat > "$vault/ops/queue/task.md" <<'EOF'
# Task
EOF
cat > "$vault/ops/observations/one.md" <<'EOF'
# Observation
EOF
cat > "$vault/ops/tensions/one.md" <<'EOF'
# Tension
EOF
cat > "$vault/ops/health/2026-04-26.md" <<'EOF'
# Health
EOF
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

Links to [[index]].
EOF
cat > "$vault/notes/invalid.md" <<'EOF'
# invalid

Links to [[missing target]].
EOF

orient_output="$("$ORIENT" "$vault" --limit 5)"
assert_contains "$orient_output" "Ars Contexta session orientation"
assert_contains "$orient_output" "Marker: present"
assert_contains "$orient_output" "ops/queue/: 1"
assert_contains "$orient_output" "Recommended next action: Review inbox pressure"

orient_json="$("$ORIENT" "$vault" --format json)"
assert_contains "$orient_json" '"arscontexta_marker": "present"'
assert_contains "$orient_json" '"inbox": 1'

valid_output="$("$VALIDATE" "$vault" --file notes/valid.md)"
assert_contains "$valid_output" "Overall: PASS"
assert_contains "$valid_output" "Findings: none"

invalid_output="$("$VALIDATE" "$vault" --file notes/invalid.md)"
assert_contains "$invalid_output" "Overall: WARN"
assert_contains "$invalid_output" "Missing YAML frontmatter"
assert_contains "$invalid_output" "Missing non-empty description"
assert_contains "$invalid_output" "Missing topics"
assert_contains "$invalid_output" "Possible unresolved wiki link: [[missing target]]"

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
changed_output="$("$VALIDATE" "$git_vault" --changed)"
assert_contains "$changed_output" "Files checked: 1"
assert_contains "$changed_output" "notes/changed.md"

summary="$tmp_dir/summary.md"
next="$tmp_dir/next.md"
cat > "$summary" <<'EOF'
Implemented session workflow scripts.
EOF
cat > "$next" <<'EOF'
Run smoke checks and commit the change.
EOF

dry_output="$("$CAPTURE" "$vault" --summary-file "$summary" --next-file "$next" --dry-run)"
assert_contains "$dry_output" "Mode: dry run"

capture_output="$("$CAPTURE" "$vault" --summary-file "$summary" --next-file "$next")"
assert_contains "$capture_output" "Wrote: ops/sessions/"
assert_contains "$capture_output" "Updated: ops/sessions/current.md"
assert_file "$vault/ops/sessions/current.md"
assert_contains "$(cat "$vault/ops/sessions/current.md")" "Implemented session workflow scripts."
assert_contains "$(cat "$vault/ops/sessions/current.md")" "Run smoke checks and commit the change."

printf 'PASS: session workflow tests\n'
