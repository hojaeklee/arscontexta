#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
GRAPH="$PROJECT_ROOT/plugins/arscontexta/scripts/graph-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/arscontexta-graph-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes" "$vault/ops"
cat > "$vault/ops/derivation-manifest.md" <<'EOF'
---
vocabulary:
  notes: notes
  note: claim
  note_plural: claims
  topic_map: topic map
  topic_map_plural: topic maps
  cmd_reflect: reflect
  cmd_reweave: reweave
---
EOF

cat > "$vault/notes/index.md" <<'EOF'
---
description: Main topic map for the fixture graph
type: moc
topics: ["[[index]]"]
---

# index

Connects [[alpha]], [[beta]], and [[gamma]].
EOF

cat > "$vault/notes/alpha.md" <<'EOF'
---
description: Alpha claim connects several notes for diagnostics
type: claim
topics: ["[[index]]"]
---

# alpha

Alpha points to [[beta|Beta Alias]], [[delta]], and [[missing target#Later]].
EOF

cat > "$vault/notes/beta.md" <<'EOF'
---
description: Beta claim links back to alpha for a two way cluster
type: claim
topics: ["[[index]]"]
---

# beta

Beta points to [[alpha]].
EOF

cat > "$vault/notes/gamma.md" <<'EOF'
---
description: Gamma claim is covered by the topic map but has little structure
type: claim
topics: ["[[index]]"]
---

# gamma
EOF

cat > "$vault/notes/delta.md" <<'EOF'
---
description: Delta claim is a small endpoint for link counting
type: claim
topics: ["[[index]]"]
---

# delta
EOF

cat > "$vault/notes/parent.md" <<'EOF'
---
description: Parent claim links two sibling notes for synthesis
type: claim
topics: ["[[index]]"]
---

# parent

Parent compares [[left]] and [[right]].
EOF

cat > "$vault/notes/left.md" <<'EOF'
---
description: Left claim is one side of an open triad
type: claim
topics: ["[[index]]"]
---

# left
EOF

cat > "$vault/notes/right.md" <<'EOF'
---
description: Right claim is the other side of an open triad
type: claim
topics: ["[[index]]"]
---

# right
EOF

cat > "$vault/notes/isolated.md" <<'EOF'
---
description: Isolated claim only points at the topic map
type: claim
topics: ["[[index]]"]
---

# isolated
EOF

health_output="$("$GRAPH" "$vault" --mode health)"
assert_contains "$health_output" "--=={ graph health }==--"
assert_contains "$health_output" "claims: 8 (plus 1 topic maps)"
assert_contains "$health_output" "topic map coverage: 38%"
assert_contains "$health_output" "Orphans (2):"
assert_contains "$health_output" "[[isolated]]"
assert_contains "$health_output" "Dangling Links (1):"
assert_contains "$health_output" "[[missing target]] from [[alpha]]"
assert_contains "$health_output" "[[index]]: 3 claims"

limit_output="$("$GRAPH" "$vault" --mode health --limit 1)"
assert_contains "$limit_output" "... 1 more omitted by --limit 1"

hubs_output="$("$GRAPH" "$vault" --mode hubs)"
assert_contains "$hubs_output" "--=={ graph hubs }==--"
assert_contains "$hubs_output" "Authorities (incoming links):"
assert_contains "$hubs_output" "[[alpha]]: 2 incoming"
assert_contains "$hubs_output" "Hubs (outgoing links):"
assert_contains "$hubs_output" "[[alpha]]: 3 outgoing"
assert_contains "$hubs_output" "Synthesizers:"
assert_contains "$hubs_output" "[[alpha]]: 2 in / 3 out"

sparse_output="$("$GRAPH" "$vault" --mode sparse)"
assert_contains "$sparse_output" "--=={ graph sparse }==--"
assert_contains "$sparse_output" "Low-link claims"
assert_contains "$sparse_output" "[[isolated]]: 1 total links"
assert_contains "$sparse_output" "Isolated components"
assert_contains "$sparse_output" "[[gamma]]"
assert_contains "$sparse_output" "[[isolated]]"
assert_contains "$sparse_output" "Action: Run reweave"

triangles_output="$("$GRAPH" "$vault" --mode triangles)"
assert_contains "$triangles_output" "--=={ graph triangles }==--"
assert_contains "$triangles_output" "Synthesis opportunities (2):"
assert_contains "$triangles_output" "[[beta]] + [[delta]] via [[alpha]]"
assert_contains "$triangles_output" "[[left]] + [[right]] via [[parent]]"
assert_not_contains "$triangles_output" "via [[index]]"

json_output="$("$GRAPH" "$vault" --mode health --format json)"
assert_contains "$json_output" '"mode": "health"'
assert_contains "$json_output" '"notes": 8'
assert_contains "$json_output" '"mocs": 1'
assert_contains "$json_output" '"dangling": 1'
assert_contains "$json_output" '"moc_coverage": 38'
assert_contains "$json_output" '"triangles"'

"$GRAPH" "$vault" --mode triangles >/dev/null
assert_not_exists "$vault/ops/graph-cache.json"
assert_not_exists "$vault/ops/graph-history.yaml"

printf 'PASS: graph-vault checks\n'
