#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATS="$PROJECT_ROOT/scripts/stats-vault.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "expected output to contain: $needle"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected file not to exist: $1"
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

printf 'PASS: stats-vault checks\n'
