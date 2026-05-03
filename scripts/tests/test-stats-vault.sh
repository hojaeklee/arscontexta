#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATS="$PROJECT_ROOT/plugins/arscontexta/scripts/stats-vault.sh"
INDEX="$PROJECT_ROOT/plugins/arscontexta/scripts/vault-index.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "expected output not to contain: $needle"
  fi
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected file not to exist: $1"
}

run_stats_capture() {
  local vault_path="$1"
  local stdout_path="$2"
  local stderr_path="$3"
  shift 3

  "$STATS" "$vault_path" "$@" >"$stdout_path" 2>"$stderr_path"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-stats-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

empty="$tmp_dir/empty"
mkdir -p "$empty/notes"
empty_output="$("$STATS" "$empty")"
assert_contains "$empty_output" "Your knowledge graph is new"
assert_contains "$empty_output" "notes: 0"

vault="$tmp_dir/vault"
mkdir -p "$vault/notes" "$vault/inbox" "$vault/ops/queue" "$vault/ops/observations" "$vault/ops/tensions" "$vault/ops/sessions" "$vault/ops/health" "$vault/ops/methodology" "$vault/self"
today="$(date +%Y-%m-%d)"
old_date="2020-01-01"
cat > "$vault/ops/derivation-manifest.md" <<'EOF'
---
vocabulary:
  notes: notes
  inbox: inbox
  note: claim
  note_plural: claims
  topic_map: topic map
  topic_map_plural: topic maps
  reflect: reflect
  rethink: rethink
---
EOF

cat > "$vault/notes/index.md" <<EOF
---
description: Main topic map
type: moc
topics: ["[[index]]"]
created: $today
---

# index

Links to [[alpha]] and [[beta]].
EOF

cat > "$vault/notes/alpha.md" <<EOF
---
description: Alpha claim connects the fixture graph
type: claim
topics: ["[[index]]"]
created: $today
---

# alpha

Links to [[beta]] and [[missing target]].
EOF

cat > "$vault/notes/beta.md" <<EOF
---
description: Beta claim completes the fixture loop
type: claim
topics: ["[[index]]"]
created: $old_date
---

# beta

Links to [[alpha]].
EOF

cat > "$vault/inbox/source.md" <<'EOF'
# Source
EOF
touch -t 202001010000 "$vault/inbox/source.md"

cat > "$vault/ops/queue/queue.json" <<'EOF'
{
  "tasks": [
    {"id": "claim-001", "status": "pending"},
    {"id": "claim-002", "status": "done"},
    {"id": "claim-003", "status": "blocked"}
  ]
}
EOF

cat > "$vault/ops/observations/obs.md" <<'EOF'
---
status: pending
---
# Observation
EOF

cat > "$vault/ops/tensions/tension.md" <<'EOF'
---
status: open
---
# Tension
EOF

touch "$vault/ops/methodology/pattern.md" "$vault/ops/sessions/session.md" "$vault/ops/health/2026-05-02.md" "$vault/self/identity.md"

output="$("$STATS" "$vault")"
assert_contains "$output" "claims: 2"
assert_contains "$output" "Connections: 8"
assert_contains "$output" "topic maps: 1"
assert_contains "$output" "Dangling: 1"
assert_contains "$output" "Schema: 100% compliant"
assert_contains "$output" "Inbox: 1 items"
assert_contains "$output" "Queue: 1 pending, 1 blocked, 1 done"
assert_contains "$output" "This week: +1 claims"
assert_contains "$output" "Self space: enabled"
assert_contains "$output" "Observations: 1 pending"
assert_contains "$output" "Tensions: 1 open"
assert_contains "$output" "Health reports: 1"
assert_contains "$output" "1 dangling links"

share_output="$("$STATS" "$vault" --share)"
assert_contains "$share_output" "## My Knowledge Graph"
assert_contains "$share_output" "**2** claims"
assert_contains "$share_output" "Built with Ars Contexta"

json_output="$("$STATS" "$vault" --format json)"
assert_contains "$json_output" '"notes": 2'
assert_contains "$json_output" '"dangling": 1'
assert_contains "$json_output" '"queue_pending": 1'
assert_contains "$json_output" '"oldest_inbox_age_days"'

yaml_vault="$tmp_dir/yaml-vault"
mkdir -p "$yaml_vault/notes" "$yaml_vault/ops/queue"
cat > "$yaml_vault/notes/one.md" <<'EOF'
---
description: One note
topics: ["[[one]]"]
---
# one
EOF
cat > "$yaml_vault/ops/queue/queue.yaml" <<'EOF'
tasks:
  - id: yaml-1
    status: pending
  - id: yaml-2
    status: completed
EOF
yaml_output="$("$STATS" "$yaml_vault")"
assert_contains "$yaml_output" "Queue: 1 pending, 0 blocked, 1 done"

"$STATS" "$vault" >/dev/null
assert_not_exists "$vault/ops/stats-history.yaml"

"$INDEX" build "$vault" >/dev/null
indexed_stdout="$tmp_dir/indexed.out"
indexed_stderr="$tmp_dir/indexed.err"
run_stats_capture "$vault" "$indexed_stdout" "$indexed_stderr"
indexed_output="$(cat "$indexed_stdout")"
indexed_errors="$(cat "$indexed_stderr")"
assert_contains "$indexed_output" "claims: 2"
assert_contains "$indexed_output" "Connections: 8"
assert_contains "$indexed_output" "Dangling: 1"
assert_not_contains "$indexed_errors" "falling back"

missing_index="$tmp_dir/missing-index"
mkdir -p "$missing_index/notes"
cat > "$missing_index/notes/one.md" <<'EOF'
---
description: One direct scan note
topics: ["[[one]]"]
---
# one
EOF
missing_stdout="$tmp_dir/missing.out"
missing_stderr="$tmp_dir/missing.err"
run_stats_capture "$missing_index" "$missing_stdout" "$missing_stderr"
assert_contains "$(cat "$missing_stdout")" "notes: 1"
assert_contains "$(cat "$missing_stderr")" "VaultIndex is missing"
assert_contains "$(cat "$missing_stderr")" "falling back to direct scan"

stale_vault="$tmp_dir/stale-vault"
mkdir -p "$stale_vault/notes"
cat > "$stale_vault/notes/one.md" <<'EOF'
---
description: One indexed note
topics: ["[[one]]"]
---
# one
EOF
"$INDEX" build "$stale_vault" >/dev/null
cat > "$stale_vault/notes/two.md" <<'EOF'
---
description: Two added after index
topics: ["[[one]]"]
---
# two
EOF
stale_stdout="$tmp_dir/stale.out"
stale_stderr="$tmp_dir/stale.err"
run_stats_capture "$stale_vault" "$stale_stdout" "$stale_stderr"
assert_contains "$(cat "$stale_stdout")" "notes: 2"
assert_contains "$(cat "$stale_stderr")" "VaultIndex is stale"
assert_contains "$(cat "$stale_stderr")" "falling back to direct scan"

corrupt_vault="$tmp_dir/corrupt-vault"
mkdir -p "$corrupt_vault/notes" "$corrupt_vault/ops/cache"
cat > "$corrupt_vault/notes/one.md" <<'EOF'
---
description: One corrupt-index fallback note
topics: ["[[one]]"]
---
# one
EOF
printf 'not sqlite\n' > "$corrupt_vault/ops/cache/index.sqlite"
corrupt_stdout="$tmp_dir/corrupt.out"
corrupt_stderr="$tmp_dir/corrupt.err"
run_stats_capture "$corrupt_vault" "$corrupt_stdout" "$corrupt_stderr"
assert_contains "$(cat "$corrupt_stdout")" "notes: 1"
assert_contains "$(cat "$corrupt_stderr")" "VaultIndex is unreadable"
assert_contains "$(cat "$corrupt_stderr")" "falling back to direct scan"

duplicate_vault="$tmp_dir/duplicate-vault"
mkdir -p "$duplicate_vault/notes/a" "$duplicate_vault/notes/b"
cat > "$duplicate_vault/notes/a/same.md" <<'EOF'
---
description: First duplicate basename note
topics: ["[[notes/b/same]]"]
---
# same

Links to [[notes/b/same]] and [[ghost]].
EOF
cat > "$duplicate_vault/notes/b/same.md" <<'EOF'
---
description: Second duplicate basename note
topics: ["[[notes/a/same]]"]
---
# same

Links to [[notes/a/same]].
EOF
"$INDEX" build "$duplicate_vault" >/dev/null
duplicate_stdout="$tmp_dir/duplicate.out"
duplicate_stderr="$tmp_dir/duplicate.err"
run_stats_capture "$duplicate_vault" "$duplicate_stdout" "$duplicate_stderr"
duplicate_output="$(cat "$duplicate_stdout")"
assert_not_contains "$(cat "$duplicate_stderr")" "falling back"
assert_contains "$duplicate_output" "notes: 2"
assert_contains "$duplicate_output" "Connections: 5"
assert_contains "$duplicate_output" "Orphans: 0"
assert_contains "$duplicate_output" "Dangling: 1"

printf 'PASS: stats-vault checks\n'
