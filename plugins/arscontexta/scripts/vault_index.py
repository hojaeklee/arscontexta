#!/usr/bin/env python3
"""Incremental SQLite index for Ars Contexta markdown vaults."""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
from dataclasses import dataclass
from typing import Any

SCHEMA_VERSION = "2"
INDEX_REL = Path("ops/cache/index.sqlite")
IGNORED_DIRS = {".git", ".obsidian", "node_modules"}
DEFAULT_SCAN_INCLUDE = [
    "notes/**",
    "self/**",
    "manual/**",
    "inbox/**",
    "ops/derivation.md",
    "ops/derivation-manifest.md",
]
DEFAULT_SCAN_EXCLUDE = [
    "archive/**",
    "imported/**",
    "attachments/**",
    "ops/cache/**",
    "ops/health/**",
    "ops/sessions/**",
    "ops/queue/archive/**",
]
WIKI_RE = re.compile(r"\[\[([^\]]+)\]\]")
HEADING_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)

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
  ordinal INTEGER NOT NULL,
  target TEXT NOT NULL,
  raw TEXT NOT NULL,
  PRIMARY KEY (source_path, ordinal),
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


@dataclass(frozen=True)
class ScanRules:
    include: list[str]
    exclude: list[str]


@dataclass(frozen=True)
class ScanResult:
    files: list[Path]
    ignored_include_miss: int
    ignored_exclude_match: int

    @property
    def ignored(self) -> int:
        return self.ignored_include_miss + self.ignored_exclude_match


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def strip_yaml_comment(line: str) -> str:
    in_single = False
    in_double = False
    for idx, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:idx]
    return line


def parse_yaml_scalar(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_inline_yaml_list(value: str) -> list[str] | None:
    value = value.strip()
    if value == "[]":
        return []
    if not (value.startswith("[") and value.endswith("]")):
        return None
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [parse_yaml_scalar(item.strip()) for item in inner.split(",") if item.strip()]


def load_scan_rules(vault: Path) -> ScanRules:
    include: list[str] | None = None
    exclude: list[str] | None = None
    config = vault / "ops/config.yaml"
    if not config.is_file():
        return ScanRules(DEFAULT_SCAN_INCLUDE.copy(), DEFAULT_SCAN_EXCLUDE.copy())

    current_key = ""
    in_scan = False
    for raw_line in config.read_text(encoding="utf-8", errors="replace").splitlines():
        line = strip_yaml_comment(raw_line).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()

        if indent == 0:
            in_scan = stripped == "scan:"
            current_key = ""
            continue
        if not in_scan:
            continue
        if indent <= 2 and stripped.endswith(":"):
            key = stripped[:-1].strip()
            if key in {"include", "exclude"}:
                current_key = key
                if key == "include" and include is None:
                    include = []
                if key == "exclude" and exclude is None:
                    exclude = []
            else:
                current_key = ""
            continue
        if indent <= 2 and ":" in stripped:
            key, raw_value = stripped.split(":", 1)
            key = key.strip()
            parsed = parse_inline_yaml_list(raw_value)
            if key == "include" and parsed is not None:
                include = parsed
                current_key = ""
            elif key == "exclude" and parsed is not None:
                exclude = parsed
                current_key = ""
            else:
                current_key = ""
            continue
        if indent >= 4 and stripped.startswith("- ") and current_key in {"include", "exclude"}:
            value = parse_yaml_scalar(stripped[2:].strip())
            if current_key == "include":
                include = [] if include is None else include
                include.append(value)
            else:
                exclude = [] if exclude is None else exclude
                exclude.append(value)

    return ScanRules(
        DEFAULT_SCAN_INCLUDE.copy() if include is None else include,
        DEFAULT_SCAN_EXCLUDE.copy() if exclude is None else exclude,
    )


def pattern_matches(pattern: str, rel: str) -> bool:
    pattern = pattern.strip().lstrip("/")
    if not pattern:
        return False
    if pattern.endswith("/**"):
        prefix = pattern[:-3].rstrip("/")
        return rel == prefix or rel.startswith(f"{prefix}/")
    return fnmatch.fnmatchcase(rel, pattern)


def matches_any(patterns: list[str], rel: str) -> bool:
    return any(pattern_matches(pattern, rel) for pattern in patterns)


def scan_markdown_files(vault: Path) -> ScanResult:
    rules = load_scan_rules(vault)
    files: list[Path] = []
    ignored_include_miss = 0
    ignored_exclude_match = 0
    for root, dirs, names in os.walk(vault):
        dirs[:] = [name for name in dirs if name not in IGNORED_DIRS]
        for name in names:
            if name.endswith(".md"):
                path = Path(root) / name
                rel = rel_id(path, vault)
                if matches_any(rules.exclude, rel):
                    ignored_exclude_match += 1
                elif not matches_any(rules.include, rel):
                    ignored_include_miss += 1
                else:
                    files.append(path)
    return ScanResult(
        files=sorted(files),
        ignored_include_miss=ignored_include_miss,
        ignored_exclude_match=ignored_exclude_match,
    )


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
    body_start = text.find("\n", end + 1)
    body = text[body_start + 1 :] if body_start != -1 else ""
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
    for match in WIKI_RE.findall(text):
        target = match.split("|", 1)[0].split("#", 1)[0].strip()
        if not target:
            continue
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


class VaultIndex:
    def __init__(self, vault: str | Path) -> None:
        self.vault = Path(vault).expanduser().resolve()
        if not self.vault.is_dir():
            raise ValueError(f"Vault path is not a directory: {vault}")
        self.index_path = self.vault / INDEX_REL
        self.force_rescan = False

    def connect(self) -> sqlite3.Connection:
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.index_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        self.ensure_schema(conn)
        return conn

    def connect_readonly(self) -> sqlite3.Connection:
        if not self.index_path.is_file():
            raise FileNotFoundError(f"VaultIndex is missing: {self.index_path}")
        conn = sqlite3.connect(f"{self.index_path.as_uri()}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def ensure_schema(self, conn: sqlite3.Connection) -> None:
        if self.links_table_needs_rebuild(conn):
            conn.execute("DROP TABLE links")
            self.force_rescan = True
        conn.executescript(SCHEMA_SQL)
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
            ("schema_version", SCHEMA_VERSION),
        )

    def links_table_needs_rebuild(self, conn: sqlite3.Connection) -> bool:
        existing = conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'links'"
        ).fetchone()
        if not existing:
            return False
        columns = [row["name"] for row in conn.execute("PRAGMA table_info(links)")]
        return "ordinal" not in columns

    def build(self) -> dict[str, Any]:
        scan = scan_markdown_files(self.vault)
        files = scan.files
        current = {rel_id(path, self.vault): path for path in files}
        summary = {
            "scanned": 0,
            "skipped": 0,
            "deleted": 0,
            "ignored": scan.ignored,
            "ignored_include_miss": scan.ignored_include_miss,
            "ignored_exclude_match": scan.ignored_exclude_match,
            "warnings": 0,
            "index": str(self.index_path),
        }
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
                previous = None if self.force_rescan else known.get(rel)
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
            conn.execute(
                "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
                ("last_build_summary_json", json_dumps(summary)),
            )
        return summary

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
            "INSERT OR REPLACE INTO links(source_path, ordinal, target, raw) VALUES (?, ?, ?, ?)",
            [
                (note.path, ordinal, link["target"], link["raw"])
                for ordinal, link in enumerate(note.links)
            ],
        )
        conn.executemany(
            "INSERT OR REPLACE INTO warnings(path, message) VALUES (?, ?)",
            [(note.path, message) for message in note.warnings],
        )

    def status(self) -> dict[str, Any]:
        with self.connect() as conn:
            indexed = conn.execute("SELECT COUNT(*) AS count FROM notes").fetchone()["count"]
            links = conn.execute("SELECT COUNT(*) AS count FROM links").fetchone()["count"]
            warnings = conn.execute("SELECT COUNT(*) AS count FROM warnings").fetchone()["count"]
            duplicate_basenames = conn.execute(
                "SELECT COUNT(*) AS count FROM (SELECT basename FROM notes GROUP BY basename HAVING COUNT(*) > 1)"
            ).fetchone()["count"]
            last_build = conn.execute("SELECT value FROM meta WHERE key = 'last_build_at'").fetchone()
            last_summary = conn.execute(
                "SELECT value FROM meta WHERE key = 'last_build_summary_json'"
            ).fetchone()
        ignored = 0
        ignored_include_miss = 0
        ignored_exclude_match = 0
        if last_summary:
            try:
                summary = json.loads(last_summary["value"])
                ignored = int(summary.get("ignored", 0))
                ignored_include_miss = int(summary.get("ignored_include_miss", 0))
                ignored_exclude_match = int(summary.get("ignored_exclude_match", 0))
            except (TypeError, ValueError, json.JSONDecodeError):
                pass
        return {
            "vault": str(self.vault),
            "index": str(self.index_path),
            "indexed_notes": indexed,
            "ignored_files": ignored,
            "ignored_include_miss": ignored_include_miss,
            "ignored_exclude_match": ignored_exclude_match,
            "links": links,
            "warnings": warnings,
            "duplicate_basenames": duplicate_basenames,
            "last_build_at": last_build["value"] if last_build else "",
        }

    def export(self) -> dict[str, Any]:
        with self.connect() as conn:
            notes = [dict(row) for row in conn.execute("SELECT * FROM notes ORDER BY path")]
            links = [
                dict(row)
                for row in conn.execute(
                    "SELECT source_path, ordinal, target, raw FROM links ORDER BY source_path, ordinal"
                )
            ]
            warnings = [
                dict(row)
                for row in conn.execute("SELECT path, message FROM warnings ORDER BY path, message")
            ]
        for note in notes:
            note["aliases"] = json.loads(note.pop("aliases_json"))
            note["frontmatter"] = json.loads(note.pop("frontmatter_json"))
            note["topics"] = json.loads(note.pop("topics_json"))
            note["is_moc"] = bool(note["is_moc"])
        return {
            "vault": str(self.vault),
            "index": str(self.index_path),
            "notes": notes,
            "links": links,
            "warnings": warnings,
        }


def print_payload(payload: dict[str, Any], fmt: str) -> None:
    if fmt == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
        return
    if {"scanned", "skipped", "deleted", "warnings"}.issubset(payload):
        print("--=={ vault index }==--")
        print(f"scanned: {payload['scanned']}")
        print(f"skipped: {payload['skipped']}")
        print(f"deleted: {payload['deleted']}")
        print(f"ignored: {payload.get('ignored', 0)}")
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
