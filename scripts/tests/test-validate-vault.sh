#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
VALIDATE="$PROJECT_ROOT/plugins/hippocampusmd/scripts/validate-vault.sh"

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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-validate-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes" "$vault/templates" "$vault/ops"
touch "$vault/.hippocampusmd"

cat > "$vault/ops/derivation-manifest.md" <<'EOF'
---
vocabulary:
  notes: notes
  templates: templates
---
EOF

cat > "$vault/templates/base-note.md" <<'EOF'
---
description: Template for validated notes
_schema:
  required: [description, topics, type]
  optional: [relevant_notes]
  enums:
    type: [claim, moc]
---

# template
EOF

cat > "$vault/notes/index.md" <<'EOF'
---
description: Entry point that gathers the main topic areas for this validation fixture
topics: ["[[index]]"]
type: moc
---

# index
EOF

cat > "$vault/notes/valid.md" <<'EOF'
---
description: Proves structured schema checks can run repeatedly while leaving vault notes unchanged
topics: ["[[index]]"]
type: claim
relevant_notes:
  - "[[index]] -- anchors the fixture topic map"
---

# valid

This links to [[index]].
EOF

valid_output="$("$VALIDATE" "$vault" --file notes/valid.md)"
assert_contains "$valid_output" "Overall: PASS"
assert_contains "$valid_output" "All checked files passed validation."

cat > "$vault/notes/missing-fields.md" <<'EOF'
---
type: claim
---

# missing fields
EOF

missing_output="$("$VALIDATE" "$vault" --file notes/missing-fields.md)"
assert_contains "$missing_output" "Overall: FAIL"
assert_contains "$missing_output" "Required field is missing or empty: description"
assert_contains "$missing_output" "Required field is missing or empty: topics"

cat > "$vault/notes/invalid-yaml.md" <<'EOF'
---
description: bad: yaml: value
topics: ["[[index]]"]
type: claim
---

# invalid yaml
EOF

yaml_output="$("$VALIDATE" "$vault" --file notes/invalid-yaml.md)"
assert_contains "$yaml_output" "Overall: FAIL"
assert_contains "$yaml_output" "Frontmatter is invalid"

cat > "$vault/notes/invalid-enum.md" <<'EOF'
---
description: Shows how invalid enum values are reported without blocking validation execution
topics: ["[[index]]"]
type: observation
---

# invalid enum
EOF

enum_output="$("$VALIDATE" "$vault" --file notes/invalid-enum.md)"
assert_contains "$enum_output" "Overall: WARN"
assert_contains "$enum_output" "type value \"observation\" is not in template enum"

cat > "$vault/notes/broken-link.md" <<'EOF'
---
description: Shows how unresolved body links are reported while leaving the note unchanged
topics: ["[[index]]"]
type: claim
---

# broken link

This links to [[missing target]].
EOF

link_output="$("$VALIDATE" "$vault" --file notes/broken-link.md)"
assert_contains "$link_output" "Overall: WARN"
assert_contains "$link_output" "Unresolved wiki link: [[missing target]]"

cat > "$vault/notes/code-links.md" <<'EOF'
---
description: Shows that example wiki links inside code are ignored during link validation
topics: ["[[index]]"]
type: claim
---

# code links

Ignore `[[inline missing]]`.

```
Ignore [[fenced missing]] too.
```
EOF

code_output="$("$VALIDATE" "$vault" --file notes/code-links.md)"
assert_contains "$code_output" "Overall: PASS"
assert_not_contains "$code_output" "inline missing"
assert_not_contains "$code_output" "fenced missing"

cat > "$vault/notes/bare-relevant.md" <<'EOF'
---
description: Shows how bare relevant note links lose relationship context for future navigation
topics: ["[[index]]"]
type: claim
relevant_notes:
  - "[[index]]"
---

# bare relevant
EOF

relevant_output="$("$VALIDATE" "$vault" --file notes/bare-relevant.md)"
assert_contains "$relevant_output" "Overall: WARN"
assert_contains "$relevant_output" "Relevant note entry lacks relationship context"

git_vault="$tmp_dir/git-vault"
cp -R "$vault" "$git_vault"
git -C "$git_vault" init --quiet
git -C "$git_vault" config user.email "test@example.com"
git -C "$git_vault" config user.name "HippocampusMD Test"
git -C "$git_vault" add .
git -C "$git_vault" commit --quiet -m "test: seed validation vault"

cat > "$git_vault/notes/untouched-invalid.md" <<'EOF'
---
type: observation
---

# untouched invalid
EOF

git -C "$git_vault" add notes/untouched-invalid.md
git -C "$git_vault" commit --quiet -m "test: add untouched invalid note"

cat > "$git_vault/notes/changed.md" <<'EOF'
---
type: claim
---

# changed
EOF

changed_output="$("$VALIDATE" "$git_vault" --changed)"
assert_contains "$changed_output" "Files checked: 1"
assert_contains "$changed_output" "notes/changed.md"
assert_not_contains "$changed_output" "notes/untouched-invalid.md"

json_output="$("$VALIDATE" "$vault" --file notes/valid.md --format json)"
assert_contains "$json_output" '"overall": "PASS"'
assert_contains "$json_output" '"files_checked": 1'

printf 'PASS: validate-vault checks\n'
