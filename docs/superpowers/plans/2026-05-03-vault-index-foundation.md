# VaultIndex Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first shared VaultIndex foundation so HippocampusMD can incrementally scan large markdown vaults and persist note/link metadata for future commands.

**Architecture:** Add a stdlib-only Python indexer with a small importable API and a shell wrapper in the plugin script layer. The indexer stores canonical vault-relative markdown paths in `ops/cache/index.sqlite`, skips unchanged files by `mtime_ns` plus size, records content hashes for changed files, and keeps parse warnings in the database instead of aborting scans.

**Tech Stack:** Bash test harness, Python 3 standard library (`sqlite3`, `hashlib`, `json`, `argparse`, `re`, `pathlib`), SQLite, existing plugin shell scripts.

---

## Issue Context

Issue #36: "Add VaultIndex foundation for incremental large-vault scans"

Parent: #34

In scope:
- Add a Python helper or CLI wrapper under `plugins/hippocampusmd/scripts/`.
- Persist the durable machine index at `ops/cache/index.sqlite`.
- Use vault-relative markdown paths as canonical IDs.
- Store basename, title/heading, aliases, mtime, size, content hash, selected frontmatter, outgoing wiki links, note type, MOC/topic-map status, and scan warnings.
- Skip unchanged files using `mtime`/size/hash.
- Provide Python-facing API plus CLI entry points for build/status/export smoke checks.

Out of scope:
- Migrating `stats-vault.sh`, `graph-vault.sh`, `vault-health.sh`, or `validate-vault.sh`.
- Advanced graph algorithms.
- Embeddings or semantic search.

## File Structure

- Create `plugins/hippocampusmd/scripts/vault_index.py`
  - Importable Python API and CLI implementation.
  - Owns scanning, parsing, SQLite schema, incremental bookkeeping, deletion handling, status, and export.
- Create `plugins/hippocampusmd/scripts/vault-index.sh`
  - Thin executable shell wrapper that delegates to `vault_index.py`.
- Create `scripts/tests/test-vault-index.sh`
  - End-to-end fixture tests for build/status/export, incremental skip behavior, deletions, duplicate basenames, and warnings.
- Modify `scripts/check-codex-plugin.sh`
  - Add bundled and cached checks for `vault-index.sh` and `vault_index.py`.
- Modify `plugins/hippocampusmd/.codex-plugin/plugin.json`
  - Bump version from `0.8.5` to `0.9.0` because this adds a backwards-compatible helper/API.

## Public API Contract

Python callers should be able to use:

```python
from vault_index import VaultIndex

index = VaultIndex("/path/to/vault")
summary = index.build()
status = index.status()
payload = index.export()
```

CLI callers should be able to use:

```bash
plugins/hippocampusmd/scripts/vault-index.sh build /path/to/vault
plugins/hippocampusmd/scripts/vault-index.sh status /path/to/vault --format json
plugins/hippocampusmd/scripts/vault-index.sh export /path/to/vault --format json
```

Text output for `build` must include the words `scanned:`, `skipped:`, `deleted:`, and `warnings:` so shell tests can assert incremental behavior without parsing JSON.

## SQLite Schema

Use this schema in `vault_index.py`:

```sql
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notes (
  path TEXT PRIMARY KEY,
  basename TEXT NOT NULL,
  title TEXT NOT NULL,
  aliases_json TEXT NOT NULL,
  mtime_ns INTEGER NOT NULL,
  size INTEGER NOT NULL,
  content_hash TEXT NOT NULL,
  frontmatter_json TEXT NOT NULL,
  description TEXT NOT NULL,
  note_type TEXT NOT NULL,
  is_moc INTEGER NOT NULL,
  created TEXT NOT NULL,
  topics_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS links (
  source_path TEXT NOT NULL,
  target TEXT NOT NULL,
  raw TEXT NOT NULL,
  PRIMARY KEY (source_path, target, raw),
  FOREIGN KEY (source_path) REFERENCES notes(path) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS warnings (
  path TEXT NOT NULL,
  message TEXT NOT NULL,
  PRIMARY KEY (path, message)
);

CREATE INDEX IF NOT EXISTS idx_notes_basename ON notes(basename);
CREATE INDEX IF NOT EXISTS idx_notes_note_type ON notes(note_type);
CREATE INDEX IF NOT EXISTS idx_notes_is_moc ON notes(is_moc);
CREATE INDEX IF NOT EXISTS idx_links_target ON links(target);
```

## Task 1: Write the Failing VaultIndex Test

**Files:**
- Create: `scripts/tests/test-vault-index.sh`

- [ ] **Step 1: Create the shell test file**

Use this structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
INDEX="$PROJECT_ROOT/plugins/hippocampusmd/scripts/vault-index.sh"

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

assert_file() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hippocampusmd-vault-index-test.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vault="$tmp_dir/vault"
mkdir -p "$vault/notes/a" "$vault/notes/b" "$vault/ops"

cat > "$vault/notes/a/duplicate.md" <<'EOF'
---
description: First duplicate basename claim
type: claim
aliases:
  - first duplicate
topics: ["[[index]]"]
created: 2026-05-03
---

# First Duplicate

Links to [[Second Duplicate]] and [[missing target]].
EOF

cat > "$vault/notes/b/duplicate.md" <<'EOF'
---
description: Second duplicate basename topic map
type: moc
aliases: ["Second Duplicate"]
topics: ["[[index]]"]
created: 2026-05-03
---

# Second Duplicate

Links to [[First Duplicate]].
EOF

cat > "$vault/notes/bad.md" <<'EOF'
---
description: Broken frontmatter never closes
type: claim

# Bad

This file should produce a parse warning without aborting the scan.
EOF

first_output="$("$INDEX" build "$vault")"
assert_contains "$first_output" "scanned: 3"
assert_contains "$first_output" "skipped: 0"
assert_contains "$first_output" "deleted: 0"
assert_contains "$first_output" "warnings: 1"
assert_file "$vault/ops/cache/index.sqlite"

second_output="$("$INDEX" build "$vault")"
assert_contains "$second_output" "scanned: 0"
assert_contains "$second_output" "skipped: 3"
assert_contains "$second_output" "deleted: 0"

status_json="$("$INDEX" status "$vault" --format json)"
assert_contains "$status_json" '"indexed_notes": 3'
assert_contains "$status_json" '"warnings": 1'
assert_contains "$status_json" '"duplicate_basenames": 1'

export_json="$("$INDEX" export "$vault" --format json)"
assert_contains "$export_json" '"path": "notes/a/duplicate.md"'
assert_contains "$export_json" '"path": "notes/b/duplicate.md"'
assert_contains "$export_json" '"basename": "duplicate"'
assert_contains "$export_json" '"target": "Second Duplicate"'
assert_contains "$export_json" '"message": "Unterminated frontmatter block."'

rm "$vault/notes/a/duplicate.md"
delete_output="$("$INDEX" build "$vault")"
assert_contains "$delete_output" "deleted: 1"

after_delete_json="$("$INDEX" export "$vault" --format json)"
assert_not_contains "$after_delete_json" '"path": "notes/a/duplicate.md"'
assert_contains "$after_delete_json" '"path": "notes/b/duplicate.md"'

printf 'PASS: vault-index checks\n'
```

- [ ] **Step 2: Make the test executable**

Run:

```bash
chmod +x scripts/tests/test-vault-index.sh
```

- [ ] **Step 3: Run the failing test**

Run:

```bash
scripts/tests/test-vault-index.sh
```

Expected: FAIL because `plugins/hippocampusmd/scripts/vault-index.sh` does not exist yet.

- [ ] **Step 4: Commit the failing test**

```bash
git add scripts/tests/test-vault-index.sh
git commit -m "test: add vault index foundation coverage"
```

## Task 2: Add the VaultIndex Python Implementation

**Files:**
- Create: `plugins/hippocampusmd/scripts/vault_index.py`

- [ ] **Step 1: Add the module shell**

Start the file with these imports, constants, and data class:

```python
#!/usr/bin/env python3
"""Incremental SQLite index for HippocampusMD markdown vaults."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
from dataclasses import dataclass
from typing import Any

SCHEMA_VERSION = "1"
INDEX_REL = Path("ops/cache/index.sqlite")
IGNORED_DIRS = {".git", ".obsidian", "node_modules"}
WIKI_RE = re.compile(r"\[\[([^\]]+)\]\]")
HEADING_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)


@dataclass(frozen=True)
class ParsedNote:
    path: str
    basename: str
    title: str
    aliases: list[str]
    mtime_ns: int
    size: int
    content_hash: str
    frontmatter: dict[str, Any]
    description: str
    note_type: str
    is_moc: bool
    created: str
    topics: list[str]
    links: list[dict[str, str]]
    warnings: list[str]
```

- [ ] **Step 2: Add path, hashing, and parsing helpers**

Use simple stdlib parsing for the frontmatter subset HippocampusMD currently needs. Unterminated frontmatter must return a warning and still parse body links/headings.

```python
def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def markdown_files(vault: Path) -> list[Path]:
    files: list[Path] = []
    for root, dirs, names in os.walk(vault):
        dirs[:] = [name for name in dirs if name not in IGNORED_DIRS]
        for name in names:
            if name.endswith(".md"):
                files.append(Path(root) / name)
    return sorted(files)


def rel_id(path: Path, vault: Path) -> str:
    return path.relative_to(vault).as_posix()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [item.strip().strip('"').strip("'") for item in inner.split(",")]
    return value.strip('"').strip("'")


def parse_frontmatter_block(lines: list[str]) -> dict[str, Any]:
    data: dict[str, Any] = {}
    current_key = ""
    for line in lines:
        if not line.strip():
            continue
        if line.startswith("  - ") and current_key:
            data.setdefault(current_key, []).append(line[4:].strip().strip('"').strip("'"))
            continue
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        current_key = key.strip()
        value = raw.strip()
        data[current_key] = [] if value == "" else parse_scalar(value)
    return data


def split_frontmatter(text: str) -> tuple[dict[str, Any], str, list[str]]:
    if not text.startswith("---\n"):
        return {}, text, []
    end = text.find("\n---", 4)
    if end == -1:
        body_start = text.find("\n\n")
        body = text[body_start + 2 :] if body_start != -1 else text
        return {}, body, ["Unterminated frontmatter block."]
    yaml_text = text[4:end]
    body = text[text.find("\n", end + 1) + 1 :]
    return parse_frontmatter_block(yaml_text.splitlines()), body, []


def normalize_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        parsed = parse_scalar(value)
        return normalize_list(parsed) if isinstance(parsed, list) else [value.strip()]
    return []


def wiki_links(text: str) -> list[dict[str, str]]:
    links: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for match in WIKI_RE.findall(text):
        target = match.split("|", 1)[0].split("#", 1)[0].strip()
        if not target:
            continue
        key = (target, match)
        if key in seen:
            continue
        seen.add(key)
        links.append({"target": target, "raw": match})
    return links


def title_from(body: str, path: Path, frontmatter: dict[str, Any]) -> str:
    title = str(frontmatter.get("title", "")).strip()
    if title:
        return title
    match = HEADING_RE.search(body)
    if match:
        return match.group(1).strip()
    return path.stem
```

- [ ] **Step 3: Add the `VaultIndex` class and schema setup**

```python
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notes (
  path TEXT PRIMARY KEY,
  basename TEXT NOT NULL,
  title TEXT NOT NULL,
  aliases_json TEXT NOT NULL,
  mtime_ns INTEGER NOT NULL,
  size INTEGER NOT NULL,
  content_hash TEXT NOT NULL,
  frontmatter_json TEXT NOT NULL,
  description TEXT NOT NULL,
  note_type TEXT NOT NULL,
  is_moc INTEGER NOT NULL,
  created TEXT NOT NULL,
  topics_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS links (
  source_path TEXT NOT NULL,
  target TEXT NOT NULL,
  raw TEXT NOT NULL,
  PRIMARY KEY (source_path, target, raw),
  FOREIGN KEY (source_path) REFERENCES notes(path) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS warnings (
  path TEXT NOT NULL,
  message TEXT NOT NULL,
  PRIMARY KEY (path, message)
);

CREATE INDEX IF NOT EXISTS idx_notes_basename ON notes(basename);
CREATE INDEX IF NOT EXISTS idx_notes_note_type ON notes(note_type);
CREATE INDEX IF NOT EXISTS idx_notes_is_moc ON notes(is_moc);
CREATE INDEX IF NOT EXISTS idx_links_target ON links(target);
"""


class VaultIndex:
    def __init__(self, vault: str | Path) -> None:
        self.vault = Path(vault).expanduser().resolve()
        if not self.vault.is_dir():
            raise ValueError(f"Vault path is not a directory: {vault}")
        self.index_path = self.vault / INDEX_REL

    def connect(self) -> sqlite3.Connection:
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.index_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        self.ensure_schema(conn)
        return conn

    def ensure_schema(self, conn: sqlite3.Connection) -> None:
        conn.executescript(SCHEMA_SQL)
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
            ("schema_version", SCHEMA_VERSION),
        )
```

- [ ] **Step 4: Add incremental build behavior**

The build method must remove deleted files, skip unchanged files, and reparse changed files:

```python
    def build(self) -> dict[str, Any]:
        files = markdown_files(self.vault)
        current = {rel_id(path, self.vault): path for path in files}
        summary = {"scanned": 0, "skipped": 0, "deleted": 0, "warnings": 0, "index": str(self.index_path)}
        with self.connect() as conn:
            known = {
                row["path"]: row
                for row in conn.execute("SELECT path, mtime_ns, size, content_hash FROM notes")
            }
            for old_path in sorted(set(known) - set(current)):
                conn.execute("DELETE FROM notes WHERE path = ?", (old_path,))
                conn.execute("DELETE FROM warnings WHERE path = ?", (old_path,))
                summary["deleted"] += 1
            for rel, path in current.items():
                stat = path.stat()
                previous = known.get(rel)
                if previous and previous["mtime_ns"] == stat.st_mtime_ns and previous["size"] == stat.st_size:
                    summary["skipped"] += 1
                    continue
                note = self.parse_note(path, rel, stat)
                if previous and previous["content_hash"] == note.content_hash:
                    conn.execute(
                        "UPDATE notes SET mtime_ns = ?, size = ?, updated_at = ? WHERE path = ?",
                        (note.mtime_ns, note.size, utc_now(), rel),
                    )
                    summary["skipped"] += 1
                    continue
                self.upsert_note(conn, note)
                summary["scanned"] += 1
                summary["warnings"] += len(note.warnings)
            conn.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", ("last_build_at", utc_now()))
        return summary
```

- [ ] **Step 5: Add parsing and persistence methods**

```python
    def parse_note(self, path: Path, rel: str, stat: os.stat_result) -> ParsedNote:
        text = path.read_text(encoding="utf-8", errors="replace")
        frontmatter, body, warnings = split_frontmatter(text)
        note_type = str(frontmatter.get("type", "")).strip()
        return ParsedNote(
            path=rel,
            basename=path.stem,
            title=title_from(body, path, frontmatter),
            aliases=normalize_list(frontmatter.get("aliases", [])),
            mtime_ns=stat.st_mtime_ns,
            size=stat.st_size,
            content_hash=sha256_text(text),
            frontmatter=frontmatter,
            description=str(frontmatter.get("description", "")).strip(),
            note_type=note_type,
            is_moc=note_type.lower() in {"moc", "topic map", "topic-map"},
            created=str(frontmatter.get("created", "")).strip(),
            topics=normalize_list(frontmatter.get("topics", [])),
            links=wiki_links(text),
            warnings=warnings,
        )

    def upsert_note(self, conn: sqlite3.Connection, note: ParsedNote) -> None:
        conn.execute(
            """
            INSERT OR REPLACE INTO notes(
              path, basename, title, aliases_json, mtime_ns, size, content_hash,
              frontmatter_json, description, note_type, is_moc, created, topics_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                note.path,
                note.basename,
                note.title,
                json_dumps(note.aliases),
                note.mtime_ns,
                note.size,
                note.content_hash,
                json_dumps(note.frontmatter),
                note.description,
                note.note_type,
                1 if note.is_moc else 0,
                note.created,
                json_dumps(note.topics),
                utc_now(),
            ),
        )
        conn.execute("DELETE FROM links WHERE source_path = ?", (note.path,))
        conn.execute("DELETE FROM warnings WHERE path = ?", (note.path,))
        conn.executemany(
            "INSERT OR REPLACE INTO links(source_path, target, raw) VALUES (?, ?, ?)",
            [(note.path, link["target"], link["raw"]) for link in note.links],
        )
        conn.executemany(
            "INSERT OR REPLACE INTO warnings(path, message) VALUES (?, ?)",
            [(note.path, message) for message in note.warnings],
        )
```

- [ ] **Step 6: Add status and export methods**

```python
    def status(self) -> dict[str, Any]:
        with self.connect() as conn:
            indexed = conn.execute("SELECT COUNT(*) AS count FROM notes").fetchone()["count"]
            links = conn.execute("SELECT COUNT(*) AS count FROM links").fetchone()["count"]
            warnings = conn.execute("SELECT COUNT(*) AS count FROM warnings").fetchone()["count"]
            duplicate_basenames = conn.execute(
                "SELECT COUNT(*) AS count FROM (SELECT basename FROM notes GROUP BY basename HAVING COUNT(*) > 1)"
            ).fetchone()["count"]
            last_build = conn.execute("SELECT value FROM meta WHERE key = 'last_build_at'").fetchone()
        return {
            "vault": str(self.vault),
            "index": str(self.index_path),
            "indexed_notes": indexed,
            "links": links,
            "warnings": warnings,
            "duplicate_basenames": duplicate_basenames,
            "last_build_at": last_build["value"] if last_build else "",
        }

    def export(self) -> dict[str, Any]:
        with self.connect() as conn:
            notes = [dict(row) for row in conn.execute("SELECT * FROM notes ORDER BY path")]
            links = [dict(row) for row in conn.execute("SELECT source_path, target, raw FROM links ORDER BY source_path, target, raw")]
            warnings = [dict(row) for row in conn.execute("SELECT path, message FROM warnings ORDER BY path, message")]
        for note in notes:
            note["aliases"] = json.loads(note.pop("aliases_json"))
            note["frontmatter"] = json.loads(note.pop("frontmatter_json"))
            note["topics"] = json.loads(note.pop("topics_json"))
            note["is_moc"] = bool(note["is_moc"])
        return {"vault": str(self.vault), "index": str(self.index_path), "notes": notes, "links": links, "warnings": warnings}
```

- [ ] **Step 7: Add CLI formatting and argument parsing**

```python
def print_payload(payload: dict[str, Any], fmt: str) -> None:
    if fmt == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
        return
    if {"scanned", "skipped", "deleted", "warnings"}.issubset(payload):
        print("--=={ vault index }==--")
        print(f"scanned: {payload['scanned']}")
        print(f"skipped: {payload['skipped']}")
        print(f"deleted: {payload['deleted']}")
        print(f"warnings: {payload['warnings']}")
        print(f"index: {payload['index']}")
        return
    for key, value in payload.items():
        print(f"{key}: {value}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="vault_index.py")
    parser.add_argument("command", choices=["build", "status", "export"])
    parser.add_argument("vault")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args(argv)
    index = VaultIndex(args.vault)
    payload = getattr(index, args.command)()
    print_payload(payload, args.format)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
```

- [ ] **Step 8: Run the failing test again**

Run:

```bash
scripts/tests/test-vault-index.sh
```

Expected: FAIL because the shell wrapper does not exist yet.

- [ ] **Step 9: Commit the Python implementation**

```bash
git add plugins/hippocampusmd/scripts/vault_index.py
git commit -m "feat: add vault index sqlite foundation"
```

## Task 3: Add the Shell Wrapper

**Files:**
- Create: `plugins/hippocampusmd/scripts/vault-index.sh`

- [ ] **Step 1: Create the wrapper**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
exec python3 "$SCRIPT_DIR/vault_index.py" "$@"
```

- [ ] **Step 2: Make the wrapper and Python file executable**

Run:

```bash
chmod +x plugins/hippocampusmd/scripts/vault-index.sh plugins/hippocampusmd/scripts/vault_index.py
```

- [ ] **Step 3: Run the VaultIndex test**

Run:

```bash
scripts/tests/test-vault-index.sh
```

Expected: PASS with `PASS: vault-index checks`.

- [ ] **Step 4: Commit the wrapper**

```bash
git add plugins/hippocampusmd/scripts/vault-index.sh plugins/hippocampusmd/scripts/vault_index.py
git commit -m "feat: expose vault index cli"
```

## Task 4: Bundle the Helper in Plugin Checks and Bump Version

**Files:**
- Modify: `scripts/check-codex-plugin.sh`
- Modify: `plugins/hippocampusmd/.codex-plugin/plugin.json`

- [ ] **Step 1: Add helper variables to `scripts/check-codex-plugin.sh`**

Near the existing helper variable block, add:

```bash
vault_index_shell_helper="$REPO_ROOT/plugins/hippocampusmd/scripts/vault-index.sh"
vault_index_python_helper="$REPO_ROOT/plugins/hippocampusmd/scripts/vault_index.py"
```

- [ ] **Step 2: Add bundled helper checks**

In the bundled helper loop, add:

```bash
  "$vault_index_shell_helper:vault index shell" \
  "$vault_index_python_helper:vault index Python"
```

- [ ] **Step 3: Add cached helper checks**

In the cached helper loop, add both filenames:

```bash
vault-index.sh vault_index.py
```

The loop should continue to emit warnings when the local Codex plugin cache has not been refreshed.

- [ ] **Step 4: Bump plugin version**

Change `plugins/hippocampusmd/.codex-plugin/plugin.json`:

```json
"version": "0.9.0",
```

- [ ] **Step 5: Run plugin check before cache refresh**

Run:

```bash
scripts/check-codex-plugin.sh
```

Expected: PASS overall or WARN for missing cached 0.9.0 plugin if the cache has not been refreshed yet. There must be zero FAIL lines.

- [ ] **Step 6: Refresh the local plugin cache**

Run:

```bash
mkdir -p "$HOME/.codex/plugins/cache/hippocampusmd/hippocampusmd/0.9.0"
/bin/cp -R plugins/hippocampusmd/. "$HOME/.codex/plugins/cache/hippocampusmd/hippocampusmd/0.9.0/"
```

- [ ] **Step 7: Run plugin check after cache refresh**

Run:

```bash
scripts/check-codex-plugin.sh
```

Expected: PASS overall with cached `vault-index.sh` and `vault_index.py` present.

- [ ] **Step 8: Commit bundle metadata**

```bash
git add scripts/check-codex-plugin.sh plugins/hippocampusmd/.codex-plugin/plugin.json
git commit -m "chore: bundle vault index helper"
```

## Task 5: Full Verification

**Files:**
- Test only

- [ ] **Step 1: Run focused tests**

```bash
scripts/tests/test-vault-index.sh
scripts/check-codex-plugin.sh
```

Expected:
- `PASS: vault-index checks`
- `scripts/check-codex-plugin.sh` exits 0 with zero FAIL lines.

- [ ] **Step 2: Run adjacent read-only command tests**

These commands are not migrated in this issue, but they guard against accidental repo-level breakage:

```bash
scripts/tests/test-stats-vault.sh
scripts/tests/test-graph-vault.sh
scripts/tests/test-vault-health.sh
scripts/tests/test-validate-vault.sh
```

Expected:
- Each script exits 0.
- Each script prints its existing `PASS:` line.

- [ ] **Step 3: Inspect working tree**

```bash
git status --short
```

Expected only intentional files are changed:
- `plugins/hippocampusmd/scripts/vault_index.py`
- `plugins/hippocampusmd/scripts/vault-index.sh`
- `scripts/tests/test-vault-index.sh`
- `scripts/check-codex-plugin.sh`
- `plugins/hippocampusmd/.codex-plugin/plugin.json`

- [ ] **Step 4: Final commit if any verification-only edits were needed**

```bash
git add plugins/hippocampusmd/scripts/vault_index.py plugins/hippocampusmd/scripts/vault-index.sh scripts/tests/test-vault-index.sh scripts/check-codex-plugin.sh plugins/hippocampusmd/.codex-plugin/plugin.json
git commit -m "fix: stabilize vault index foundation"
```

Only run this commit if Step 1 or Step 2 required code changes after the previous commits.

## Self-Review

Spec coverage:
- Incremental unchanged-file skip is covered by Task 1 and Task 2.
- Duplicate basenames are covered by canonical `path` primary keys and the duplicate basename test.
- Parse warnings are covered by the unterminated frontmatter fixture and `warnings` table.
- Deletion handling is covered by the remove-and-rescan test.
- Build/status/export CLI smoke checks are covered by the shell test.
- Python-facing API is covered by the public `VaultIndex` class contract.
- Plugin-facing SemVer bump and local cache refresh are covered by Task 4.

Out-of-scope guardrails:
- Existing stats, graph, health, and validate scripts remain unchanged except for adjacent verification.
- No embeddings, semantic search, or advanced graph algorithms are introduced.

Plan complete when:
- Focused and adjacent tests pass.
- `scripts/check-codex-plugin.sh` passes.
- Local plugin cache contains version `0.9.0`.
- Changes are committed with Conventional Commits.
