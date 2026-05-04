# Indexed Graph Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `graph-vault.sh --mode health` to use persisted VaultIndex graph data when available, while preserving the existing full-scan fallback.

**Architecture:** Keep `plugins/arscontexta/scripts/graph-vault.sh` as the public graph CLI and add a health-only indexed graph loader inside its Ruby implementation. The indexed path reads `ops/cache/index.sqlite`, resolves wiki-link targets to vault-relative canonical IDs, computes health metrics from indexed rows, and falls back to the existing markdown scan when the index is absent, unreadable, stale, or unusable.

**Tech Stack:** Ruby stdlib plus `sqlite3` Ruby gem when available, Bash test harness, existing Python-backed `VaultIndex`, SQLite database at `ops/cache/index.sqlite`, existing plugin shell verification.

---

## Issue Context

Issue #39: "Migrate graph-vault core health mode to indexed graph data"

Parent: #34

In scope:
- Teach `plugins/arscontexta/scripts/graph-vault.sh --mode health` to use indexed outgoing links, incoming counts, MOC/topic-map coverage, dangling links, and orphan candidates when available.
- Preserve current fallback behavior when no index exists.
- Use vault-relative canonical IDs internally.
- Keep basename/title lookup user-friendly in output.
- Add duplicate-basename and dangling-link tests that prove indexed graph health is path-aware.

Out of scope:
- New graph modes such as neighborhood, component, or sparse.
- Migrating `stats-vault.sh`, `vault-health.sh`, or `validate-vault.sh`.
- Deep graph algorithms beyond current health behavior.

## File Structure

- Modify `plugins/arscontexta/scripts/graph-vault.sh`
  - Add optional `sqlite3` loading for indexed health.
  - Add index freshness/status detection.
  - Add path-aware indexed graph construction.
  - Keep existing markdown-scan graph construction as fallback and for non-health modes.
  - Keep text and JSON output shapes compatible with current tests.
- Modify `scripts/tests/test-graph-vault.sh`
  - Keep all current graph tests passing.
  - Add an indexed duplicate-basename fixture.
  - Add missing-index fallback assertions.
  - Add stale-index fallback assertions.
- Modify `plugins/arscontexta/.codex-plugin/plugin.json`
  - Bump version from `0.11.0` to `0.11.1` because this is a plugin-facing fix/internal performance improvement.
- No schema change is planned for `plugins/arscontexta/scripts/vault_index.py`.
  - Existing `notes.path`, `notes.basename`, `notes.title`, `notes.aliases_json`, `notes.description`, `notes.is_moc`, and `links.source_path/target/raw` are sufficient.
  - If implementation proves the Ruby environment cannot load `sqlite3`, keep fallback behavior and make the test skip indexed-path assertions with an explicit message rather than requiring a new dependency.

## Behavioral Contract

`graph-vault.sh --mode health` should select indexed mode only when all of these are true:
- `ops/cache/index.sqlite` exists.
- Ruby can `require "sqlite3"`.
- The index has at least one row in `notes`.
- Every indexed markdown file still exists.
- No included markdown file under current scan rules is newer than the index file.

When indexed mode is selected:
- Internal node IDs must be canonical vault-relative paths such as `notes/projects/alpha.md`.
- Display IDs should remain friendly: `[[alpha]]` when unique, and `[[projects/alpha]]` or `[[notes/projects/alpha.md]]` when disambiguation is needed.
- Dangling-link detection must resolve targets by exact path, basename, title, and aliases before marking a link dangling.
- If a basename is duplicated, basename-only links must be treated as ambiguous and reported explicitly instead of silently resolving to the wrong file.
- JSON output should add a small `index` object without changing existing `counts` or `findings` keys:

```json
{
  "index": {
    "mode": "indexed",
    "path": "/vault/ops/cache/index.sqlite",
    "status": "fresh"
  }
}
```

When indexed mode is not selected:
- Existing full-scan behavior and output should continue to work.
- JSON output should report the recoverable fallback reason:

```json
{
  "index": {
    "mode": "scan",
    "path": "/vault/ops/cache/index.sqlite",
    "status": "missing"
  }
}
```

Text output may include one concise status line after the heading:

```text
Index: using fresh VaultIndex
```

or

```text
Index: full scan fallback (missing index; run vault-index.sh build)
```

## Task 1: Add Tests for Indexed Health Fallbacks

**Files:**
- Modify: `scripts/tests/test-graph-vault.sh`

- [ ] **Step 1: Add an index helper path and optional sqlite detection after the `GRAPH` variable**

```bash
INDEX="$PROJECT_ROOT/plugins/arscontexta/scripts/vault-index.sh"

has_ruby_sqlite3() {
  ruby -e 'require "sqlite3"' >/dev/null 2>&1
}
```

- [ ] **Step 2: Add missing-index fallback assertions after the existing `health_output` assertions**

```bash
assert_contains "$health_output" "claims: 8 (plus 1 topic maps)"
assert_contains "$health_output" "Index: full scan fallback"
assert_contains "$health_output" "missing index"
```

- [ ] **Step 3: Add JSON fallback assertions after the existing `json_output` assertions**

```bash
assert_contains "$json_output" '"mode": "scan"'
assert_contains "$json_output" '"status": "missing"'
```

- [ ] **Step 4: Run the graph test to verify it fails before implementation**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: FAIL with `expected output to contain: Index: full scan fallback`.

- [ ] **Step 5: Commit the failing fallback test**

```bash
git add scripts/tests/test-graph-vault.sh
git commit -m "test: cover graph health index fallback"
```

## Task 2: Add Indexed Duplicate-Basename Fixture

**Files:**
- Modify: `scripts/tests/test-graph-vault.sh`

- [ ] **Step 1: Append the indexed duplicate-basename fixture before the final PASS line**

```bash
if has_ruby_sqlite3; then
  indexed_vault="$tmp_dir/indexed-vault"
  mkdir -p "$indexed_vault/notes/team-a" "$indexed_vault/notes/team-b" "$indexed_vault/ops"

  cat > "$indexed_vault/ops/derivation-manifest.md" <<'EOF'
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

  cat > "$indexed_vault/notes/index.md" <<'EOF'
---
description: Indexed topic map
type: moc
topics: ["[[index]]"]
---

# index

Connects [[Alpha Note]], [[team-a/shared]], and [[team-b/shared]].
EOF

  cat > "$indexed_vault/notes/alpha.md" <<'EOF'
---
description: Alpha note links by path and by ambiguous basename
type: claim
aliases: ["Alpha Note"]
topics: ["[[index]]"]
---

# Alpha Note

Alpha links to [[team-a/shared]], [[shared]], and [[missing target]].
EOF

  cat > "$indexed_vault/notes/team-a/shared.md" <<'EOF'
---
description: Team A shared note
type: claim
aliases: ["Team A Shared"]
topics: ["[[index]]"]
---

# Shared

Team A links back to [[Alpha Note]].
EOF

  cat > "$indexed_vault/notes/team-b/shared.md" <<'EOF'
---
description: Team B shared note
type: claim
aliases: ["Team B Shared"]
topics: ["[[index]]"]
---

# Shared

Team B has only topic-map coverage.
EOF

  "$INDEX" build "$indexed_vault" >/dev/null
  indexed_health="$("$GRAPH" "$indexed_vault" --mode health)"
  assert_contains "$indexed_health" "Index: using fresh VaultIndex"
  assert_contains "$indexed_health" "claims: 3 (plus 1 topic maps)"
  assert_contains "$indexed_health" "topic map coverage: 100%"
  assert_contains "$indexed_health" "Orphans (0):"
  assert_contains "$indexed_health" "Dangling Links (2):"
  assert_contains "$indexed_health" "[[shared]] from [[alpha]] -- ambiguous target"
  assert_contains "$indexed_health" "[[missing target]] from [[alpha]]"

  indexed_json="$("$GRAPH" "$indexed_vault" --mode health --format json)"
  assert_contains "$indexed_json" '"mode": "indexed"'
  assert_contains "$indexed_json" '"status": "fresh"'
  assert_contains "$indexed_json" '"id": "notes/team-a/shared.md"'
  assert_contains "$indexed_json" '"id": "notes/team-b/shared.md"'
  assert_contains "$indexed_json" '"target": "shared"'
  assert_contains "$indexed_json" '"reason": "ambiguous"'
else
  printf 'SKIP: indexed graph health duplicate-basename checks require ruby sqlite3\n'
fi
```

- [ ] **Step 2: Run the graph test to verify indexed fixture fails before implementation**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: FAIL at `Index: using fresh VaultIndex` when `sqlite3` is available, or PASS with a visible SKIP line if `sqlite3` is not available.

- [ ] **Step 3: Commit the failing indexed fixture**

```bash
git add scripts/tests/test-graph-vault.sh
git commit -m "test: cover indexed graph health duplicate basenames"
```

## Task 3: Refactor Graph Loading Behind a Builder Interface

**Files:**
- Modify: `plugins/arscontexta/scripts/graph-vault.sh`

- [ ] **Step 1: Add optional sqlite support near the existing `require` lines**

```ruby
begin
  require "sqlite3"
  SQLITE_AVAILABLE = true
rescue LoadError
  SQLITE_AVAILABLE = false
end
```

- [ ] **Step 2: Add helper methods after `relpath`**

```ruby
def path_id(path, root)
  relpath(path, root)
end

def display_id_for(id, display_by_id)
  display_by_id.fetch(id, id.sub(%r{\Anotes/}, "").sub(/\.md\z/, ""))
end

def display_link(id, display_by_id)
  "[[#{display_id_for(id, display_by_id)}]]"
end

def index_path(root)
  File.join(root, "ops/cache/index.sqlite")
end
```

- [ ] **Step 3: Move current full-scan graph construction into `build_scan_graph(root, vocab)`**

Move the contiguous top-level block that currently starts with `note_files = markdown_files(vault_abs, vocab["notes"])` and ends with `triangles = triangles.sort_by { |entry| [entry[:parent], entry[:left], entry[:right]] }`. Change only the root variable from `vault_abs` to `root`, and return the payload hash shown here:

```ruby
def build_scan_graph(root, vocab)
  note_files = markdown_files(root, vocab["notes"])
  metadata = {}
  note_files.each { |path| metadata[path] = frontmatter(path) }
  moc_files = note_files.select { |path| metadata[path]["type"].to_s.downcase == "moc" }
  content_files = note_files - moc_files
  large_vault = note_files.length > 200

  nodes = {}
  note_files.each do |path|
    id = File.basename(path, ".md")
    nodes[id] = {
      id: id,
      path: path,
      rel: relpath(path, root),
      description: metadata[path]["description"].to_s.strip,
      moc: moc_files.include?(path),
      outgoing: wiki_links(File.read(path))
    }
  end

  compute_graph_payload(nodes, content_files.map { |path| File.basename(path, ".md") }, moc_files.map { |path| File.basename(path, ".md") }, large_vault, vocab, {
    mode: "scan",
    path: index_path(root),
    status: File.exist?(index_path(root)) ? "stale-or-unusable" : "missing"
  })
end
```

- [ ] **Step 4: Create `compute_graph_payload` around the shared metric logic**

The method should accept canonical IDs and return the current `counts`, `findings`, and `suggestions` values plus `index_info`:

```ruby
def resolved_outgoing_ids(node)
  node[:outgoing].map { |link| link.is_a?(Hash) ? link[:id] : link }.compact
end

def outgoing_link_raw(link)
  link.is_a?(Hash) ? link[:raw] : link
end

def outgoing_link_reason(link)
  link.is_a?(Hash) ? link[:reason] : nil
end

def compute_graph_payload(nodes, content_ids, moc_ids, large_vault, vocab, index_info)
  target_ids = nodes.keys.to_set
  incoming = Hash.new { |hash, key| hash[key] = Set.new }
  dangling = []

  nodes.each_value do |node|
    node[:outgoing].each do |link|
      target = link.is_a?(Hash) ? link[:id] : link
      raw = link.is_a?(Hash) ? link[:raw] : link
      reason = link.is_a?(Hash) ? link[:reason] : nil
      if target && target_ids.include?(target)
        incoming[target] << node[:id] unless target == node[:id]
      else
        dangling << { target: raw, source: node[:id], reason: reason }.compact
      end
    end
  end

  link_count = nodes.values.sum { |node| node[:outgoing].length }
  graph_density = density(link_count, [content_ids.length, 1].max)
  orphans = content_ids.select { |id| incoming[id].empty? }.sort
  moc_covered = content_ids.count do |id|
    nodes.values.any? { |node| node[:moc] && node[:outgoing].any? { |link| (link.is_a?(Hash) ? link[:id] : link) == id } }
  end
  coverage = pct(moc_covered, content_ids.length)

  undirected = Hash.new { |hash, key| hash[key] = Set.new }
  content_ids.each { |id| undirected[id] }
  nodes.each_value do |node|
    next if node[:moc]

    resolved_outgoing_ids(node).each do |target|
      next unless content_ids.include?(target)

      undirected[node[:id]] << target
      undirected[target] << node[:id]
    end
  end
  components = connected_components(content_ids, undirected)
  isolated = components.select { |component| component.length == 1 }.flatten

  authorities = content_ids.map do |id|
    { id: id, incoming: incoming[id].length, outgoing: (resolved_outgoing_ids(nodes[id]) & target_ids.to_a).length, description: nodes[id][:description] }
  end.sort_by { |entry| [-entry[:incoming], entry[:id]] }
  hubs = authorities.sort_by { |entry| [-entry[:outgoing], entry[:id]] }
  synthesizers = authorities.select { |entry| entry[:incoming] > 0 && entry[:outgoing] > 0 }
                            .sort_by { |entry| [-(entry[:incoming] + entry[:outgoing]), entry[:id]] }

  low_link = content_ids.map do |id|
    total = incoming[id].length + (resolved_outgoing_ids(nodes[id]) & target_ids.to_a).length
    { id: id, links: total, description: nodes[id][:description] }
  end.select { |entry| entry[:links] < 2 }.sort_by { |entry| [entry[:links], entry[:id]] }

  triangles = []
  unless large_vault
    nodes.each_value do |parent|
      next if parent[:moc]

      linked = (resolved_outgoing_ids(parent) & content_ids).sort
      linked.combination(2) do |left, right|
        next if resolved_outgoing_ids(nodes[left]).include?(right) || resolved_outgoing_ids(nodes[right]).include?(left)

        triangles << {
          parent: parent[:id],
          left: left,
          right: right,
          left_description: nodes[left][:description],
          right_description: nodes[right][:description]
        }
      end
    end
  end
  triangles = triangles.sort_by { |entry| [entry[:parent], entry[:left], entry[:right]] }

  counts = {
    notes: content_ids.length,
    mocs: moc_ids.length,
    links: link_count,
    density: graph_density,
    orphans: orphans.length,
    dangling: dangling.length,
    moc_coverage: coverage,
    components: components.length,
    isolated: isolated.length,
    large_vault_approximate: large_vault
  }

  findings = {
    orphans: orphans.map { |id| { id: id, description: nodes[id][:description] } },
    dangling: dangling.uniq { |entry| [entry[:target], entry[:source], entry[:reason]] },
    moc_sizes: moc_ids.map { |id| { id: id, size: (resolved_outgoing_ids(nodes[id]) & content_ids).length } }.sort_by { |entry| [-entry[:size], entry[:id]] },
    authorities: authorities,
    hubs: hubs,
    synthesizers: synthesizers,
    low_link: low_link,
    isolated: isolated.map { |id| { id: id, description: nodes[id][:description] } },
    components: components.map { |component| { size: component.length, nodes: component } },
    triangles: triangles
  }

  suggestions = []
  suggestions << "Run #{vocab["reflect"]} on orphan #{vocab["note_plural"]} to find first connections." if orphans.any?
  suggestions << "Create missing #{vocab["note_plural"]} or update stale wiki links." if dangling.any?
  suggestions << "Run #{vocab["reweave"]} on low-link #{vocab["note_plural"]} to strengthen traversal." if low_link.any?
  suggestions << "Evaluate top triangle pairs as synthesis candidates." if triangles.any?
  suggestions << "Metrics approximate for large vault; run narrower graph modes for detailed review." if large_vault

  { counts: counts, findings: findings, suggestions: suggestions, index_info: index_info }
end
```

The returned suggestions must keep the current vocabulary-aware wording by reading `reflect`, `reweave`, and `note_plural` from the `vocab` argument.

- [ ] **Step 5: Run existing graph tests**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: existing mode assertions still pass except the new index status assertions until output is wired.

- [ ] **Step 6: Commit the loader refactor**

```bash
git add plugins/arscontexta/scripts/graph-vault.sh
git commit -m "refactor: isolate graph health payload construction"
```

## Task 4: Implement Path-Aware Indexed Health Loading

**Files:**
- Modify: `plugins/arscontexta/scripts/graph-vault.sh`

- [ ] **Step 1: Add index freshness detection after helper methods**

```ruby
def scan_markdown_rels(root)
  Dir.glob(File.join(root, "**", "*.md")).reject do |path|
    rel = relpath(path, root)
    rel.start_with?(".git/", ".obsidian/", "node_modules/", "archive/", "imported/", "attachments/", "ops/cache/", "ops/health/", "ops/sessions/", "ops/queue/archive/")
  end.sort
end

def indexed_health_status(root)
  sqlite = index_path(root)
  return { usable: false, status: "missing", reason: "missing index" } unless File.file?(sqlite)
  return { usable: false, status: "sqlite-unavailable", reason: "ruby sqlite3 unavailable" } unless SQLITE_AVAILABLE

  index_mtime = File.mtime(sqlite)
  changed = scan_markdown_rels(root).find { |path| File.mtime(path) > index_mtime }
  return { usable: false, status: "stale", reason: "stale index; run vault-index.sh build", changed: relpath(changed, root) } if changed

  { usable: true, status: "fresh", reason: "fresh" }
end
```

- [ ] **Step 2: Add SQLite row loaders**

```ruby
def indexed_rows(root)
  db = SQLite3::Database.new(index_path(root))
  db.results_as_hash = true
  notes = db.execute("SELECT path, basename, title, aliases_json, description, is_moc FROM notes ORDER BY path")
  links = db.execute("SELECT source_path, target, raw FROM links ORDER BY source_path, target, raw")
  [notes, links]
ensure
  db&.close
end
```

- [ ] **Step 3: Add target resolver maps**

```ruby
def add_lookup(lookup, key, id)
  normalized = key.to_s.strip
  return if normalized.empty?

  lookup[normalized] << id
end

def build_index_lookup(notes)
  lookup = Hash.new { |hash, key| hash[key] = Set.new }
  notes.each do |note|
    id = note["path"]
    add_lookup(lookup, id, id)
    add_lookup(lookup, id.sub(/\.md\z/, ""), id)
    add_lookup(lookup, id.sub(%r{\Anotes/}, "").sub(/\.md\z/, ""), id)
    add_lookup(lookup, note["basename"], id)
    add_lookup(lookup, note["title"], id)
    JSON.parse(note["aliases_json"].to_s).each { |name| add_lookup(lookup, name, id) }
  rescue JSON::ParserError
    add_lookup(lookup, note["basename"], id)
  end
  lookup
end
```

- [ ] **Step 4: Add target resolution**

```ruby
def resolve_index_target(raw_target, lookup)
  candidates = lookup[raw_target.to_s.strip].to_a.sort
  return { id: candidates.first, raw: raw_target } if candidates.length == 1
  return { id: nil, raw: raw_target, reason: "ambiguous" } if candidates.length > 1

  { id: nil, raw: raw_target, reason: "missing" }
end
```

- [ ] **Step 5: Add indexed graph builder**

```ruby
def build_indexed_health_graph(root)
  status = indexed_health_status(root)
  return nil unless status[:usable]

  notes, links = indexed_rows(root)
  return nil if notes.empty?

  lookup = build_index_lookup(notes)
  nodes = {}
  display_counts = Hash.new(0)
  notes.each { |note| display_counts[note["basename"]] += 1 }
  display_by_id = {}

  notes.each do |note|
    id = note["path"]
    friendly = if display_counts[note["basename"]] == 1
                 note["basename"]
               else
                 id.sub(%r{\Anotes/}, "").sub(/\.md\z/, "")
               end
    display_by_id[id] = friendly
    nodes[id] = {
      id: id,
      path: File.join(root, id),
      rel: id,
      description: note["description"].to_s.strip,
      moc: note["is_moc"].to_i == 1,
      outgoing: [],
      display: friendly
    }
  end

  links.each do |link|
    node = nodes[link["source_path"]]
    next unless node

    node[:outgoing] << resolve_index_target(link["target"], lookup)
  end

  content_ids = nodes.values.reject { |node| node[:moc] }.map { |node| node[:id] }.sort
  moc_ids = nodes.values.select { |node| node[:moc] }.map { |node| node[:id] }.sort
  compute_graph_payload(nodes, content_ids, moc_ids, nodes.length > 200, vocab, {
    mode: "indexed",
    path: index_path(root),
    status: status[:status]
  }.compact.merge(display_by_id: display_by_id))
rescue SQLite3::Exception => e
  {
    error: e.message,
    index_info: {
      mode: "scan",
      path: index_path(root),
      status: "unreadable",
      reason: "unreadable index; run vault-index.sh build"
    }
  }
end
```

- [ ] **Step 6: Select indexed health before scan graph**

Replace the top-level graph construction with:

```ruby
indexed_payload = mode == "health" ? build_indexed_health_graph(vault_abs) : nil
if indexed_payload && !indexed_payload[:error]
  payload = indexed_payload
else
  payload = build_scan_graph(vault_abs, vocab)
  if indexed_payload && indexed_payload[:index_info]
    payload[:index_info] = indexed_payload[:index_info]
  end
end
counts = payload[:counts]
findings = payload[:findings]
suggestions = payload[:suggestions]
index_info = payload[:index_info]
display_by_id = index_info.delete(:display_by_id) || {}
```

- [ ] **Step 7: Run graph tests**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: PASS when `sqlite3` is available or PASS with `SKIP: indexed graph health duplicate-basename checks require ruby sqlite3` when it is not.

- [ ] **Step 8: Commit indexed health loading**

```bash
git add plugins/arscontexta/scripts/graph-vault.sh
git commit -m "feat: use VaultIndex for graph health"
```

## Task 5: Update Text and JSON Output

**Files:**
- Modify: `plugins/arscontexta/scripts/graph-vault.sh`

- [ ] **Step 1: Include `index` metadata in JSON output**

Change JSON generation to:

```ruby
if format == "json"
  puts JSON.pretty_generate(
    vault: vault_abs,
    mode: mode,
    vocabulary: vocab,
    index: index_info,
    counts: counts,
    findings: findings,
    suggestions: suggestions
  )
  exit 0
end
```

- [ ] **Step 2: Print index status in text health output**

In the `when "health"` branch, after the blank line following the heading:

```ruby
if index_info[:mode] == "indexed"
  puts "Index: using fresh VaultIndex"
else
  puts "Index: full scan fallback (#{index_info[:reason] || index_info[:status]}; run vault-index.sh build)"
end
puts
```

- [ ] **Step 3: Use friendly display links for health lists**

Update health output formatters:

```ruby
print_limited(findings[:orphans].map { |entry| "  - #{display_link(entry[:id], display_by_id)}#{entry[:description].empty? ? "" : " -- #{entry[:description]}"}" }, limit)

print_limited(findings[:dangling].map do |entry|
  suffix = entry[:reason] && entry[:reason] != "missing" ? " -- #{entry[:reason]} target" : ""
  "  - [[#{entry[:target]}]] from #{display_link(entry[:source], display_by_id)}#{suffix}"
end, limit)

print_limited(findings[:moc_sizes].map { |entry| "  - #{display_link(entry[:id], display_by_id)}: #{entry[:size]} #{vocab["note_plural"]}" }, limit)
```

- [ ] **Step 4: Preserve legacy display for non-indexed and non-health modes**

Set `display_by_id = {}` for scan mode so existing `[[alpha]]`, `[[index]]`, and triangle output remains unchanged.

- [ ] **Step 5: Run graph tests**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: PASS.

- [ ] **Step 6: Commit output metadata**

```bash
git add plugins/arscontexta/scripts/graph-vault.sh
git commit -m "fix: report graph health index status"
```

## Task 6: Add Stale Index Recovery Test

**Files:**
- Modify: `scripts/tests/test-graph-vault.sh`

- [ ] **Step 1: Add stale index assertions inside the indexed fixture block**

Place after the first `indexed_json` assertions:

```bash
sleep 1
cat >> "$indexed_vault/notes/alpha.md" <<'EOF'

Fresh edit after the index was built.
EOF

stale_output="$("$GRAPH" "$indexed_vault" --mode health)"
assert_contains "$stale_output" "Index: full scan fallback"
assert_contains "$stale_output" "stale index"
assert_contains "$stale_output" "claims: 3 (plus 1 topic maps)"

"$INDEX" build "$indexed_vault" >/dev/null
rebuilt_output="$("$GRAPH" "$indexed_vault" --mode health)"
assert_contains "$rebuilt_output" "Index: using fresh VaultIndex"
```

- [ ] **Step 2: Run graph tests**

Run:

```bash
scripts/tests/test-graph-vault.sh
```

Expected: PASS, with stale fallback followed by recoverable indexed mode after rebuild.

- [ ] **Step 3: Commit stale recovery coverage**

```bash
git add scripts/tests/test-graph-vault.sh
git commit -m "test: cover stale graph health index recovery"
```

## Task 7: Bump Plugin Version and Verify

**Files:**
- Modify: `plugins/arscontexta/.codex-plugin/plugin.json`

- [ ] **Step 1: Bump plugin version**

Change:

```json
"version": "0.11.0"
```

to:

```json
"version": "0.11.1"
```

- [ ] **Step 2: Run relevant tests**

Run:

```bash
scripts/tests/test-vault-index.sh
scripts/tests/test-graph-vault.sh
scripts/check-codex-plugin.sh
```

Expected:
- `PASS: vault-index checks`
- `PASS: graph-vault checks`
- `scripts/check-codex-plugin.sh` completes with no `FAIL` lines.

- [ ] **Step 3: Refresh local plugin cache**

Run:

```bash
/bin/cp -R plugins/arscontexta /Users/hlee/.codex/plugins/cache/agenticnotetaking/arscontexta/0.11.1
```

Expected: the cache path exists and contains the updated `graph-vault.sh`, `vault-index.sh`, and `plugin.json`.

- [ ] **Step 4: Commit final plugin-facing changes**

```bash
git add plugins/arscontexta/scripts/graph-vault.sh scripts/tests/test-graph-vault.sh plugins/arscontexta/.codex-plugin/plugin.json
git commit -m "fix: migrate graph health to VaultIndex"
```

## Acceptance Checklist

- [ ] Existing graph health, hubs, sparse, triangles, and JSON tests still pass.
- [ ] `graph-vault.sh --mode health` uses indexed graph data when `ops/cache/index.sqlite` is fresh and Ruby `sqlite3` is available.
- [ ] Missing, stale, unreadable, or unsupported index behavior falls back to the full scan with an explicit recoverable status.
- [ ] Indexed health computes incoming links, outgoing links, dangling links, orphan candidates, and topic-map coverage from indexed rows.
- [ ] Internal IDs in indexed mode are vault-relative paths, not basenames.
- [ ] Duplicate basenames do not collapse nodes.
- [ ] Ambiguous basename-only links are reported as ambiguous dangling targets.
- [ ] User-facing output remains friendly and disambiguates duplicates.
- [ ] `scripts/tests/test-vault-index.sh` passes.
- [ ] `scripts/tests/test-graph-vault.sh` passes.
- [ ] `scripts/check-codex-plugin.sh` passes.
- [ ] `plugins/arscontexta/.codex-plugin/plugin.json` has a patch version bump.
- [ ] Local plugin cache is refreshed to the new version.

## Self-Review Notes

- Spec coverage: every issue acceptance criterion maps to at least one task above.
- Placeholder scan: implementation-dependent code blocks identify exact methods, signatures, output strings, and commands.
- Type consistency: indexed nodes use canonical IDs such as `notes/team-a/shared.md` internally; display helpers are the only place that removes `notes/` or `.md`.
- Risk: Ruby `sqlite3` may not be installed in all local environments. The plan treats that as recoverable fallback for users and a skip for the indexed-path shell test, while preserving current full-scan behavior.
