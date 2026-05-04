#!/usr/bin/env python3
"""Incremental SQLite index for HippocampusMD markdown vaults."""

from __future__ import annotations

import argparse
import csv
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
EXPORT_REL = Path("ops/cache/exports")
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


def add_lookup_value(lookup: dict[str, set[str]], key: str, path: str) -> None:
    key = str(key).strip()
    if key:
        lookup.setdefault(key, set()).add(path)


def build_target_lookup(notes: list[dict[str, Any]]) -> dict[str, set[str]]:
    lookup: dict[str, set[str]] = {}
    for note in notes:
        path = str(note["path"])
        path_no_suffix = path[:-3] if path.endswith(".md") else path
        add_lookup_value(lookup, path, path)
        add_lookup_value(lookup, path_no_suffix, path)
        add_lookup_value(lookup, str(note.get("basename", "")), path)
        add_lookup_value(lookup, str(note.get("title", "")), path)
        for alias in normalize_list(note.get("aliases", [])):
            add_lookup_value(lookup, alias, path)
    return lookup


def resolve_target(target: str, lookup: dict[str, set[str]]) -> tuple[str, str]:
    normalized = target[:-3] if target.endswith(".md") else target
    matches = lookup.get(normalized) or lookup.get(target) or set()
    if len(matches) == 1:
        return "resolved", next(iter(matches))
    if len(matches) > 1:
        return "ambiguous", ""
    return "missing", ""


def csv_cell(value: Any) -> Any:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (list, dict)):
        return json_dumps(value)
    if value is None:
        return ""
    return value


def markdown_cell(value: Any) -> str:
    text = str(csv_cell(value))
    return text.replace("|", "\\|").replace("\n", " ")


def markdown_table(headers: list[str], rows: list[dict[str, Any]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _header in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(markdown_cell(row.get(header, "")) for header in headers) + " |")
    if not rows:
        lines.append("| " + " | ".join("" for _header in headers) + " |")
    return lines


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
        self.force_rescan = self.ensure_schema(conn)
        return conn

    def connect_readonly(self) -> sqlite3.Connection:
        if not self.index_path.is_file():
            raise FileNotFoundError(f"VaultIndex is missing: {self.index_path}")
        conn = sqlite3.connect(f"{self.index_path.as_uri()}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def ensure_schema(self, conn: sqlite3.Connection) -> bool:
        links_invalidated = False
        if self.links_table_needs_rebuild(conn):
            conn.execute("DROP TABLE links")
            links_invalidated = True
        conn.executescript(SCHEMA_SQL)
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
            ("schema_version", SCHEMA_VERSION),
        )
        return links_invalidated

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

        lookup = build_target_lookup(notes)
        resolved_links: list[dict[str, Any]] = []
        incoming: dict[str, set[str]] = {str(note["path"]): set() for note in notes}
        for link in links:
            status, resolved_path = resolve_target(str(link["target"]), lookup)
            enriched = {
                **link,
                "resolution_status": status,
                "resolved_path": resolved_path,
            }
            resolved_links.append(enriched)
            source_path = str(link["source_path"])
            if status == "resolved" and resolved_path and resolved_path != source_path:
                incoming.setdefault(resolved_path, set()).add(source_path)

        dangling_links = sorted(
            [link for link in resolved_links if link["resolution_status"] == "missing"],
            key=lambda link: (str(link["target"]), str(link["source_path"]), int(link["ordinal"])),
        )
        orphan_candidates = [
            {
                "path": note["path"],
                "basename": note["basename"],
                "title": note["title"],
                "description": note["description"],
            }
            for note in notes
            if not note["is_moc"] and not incoming.get(str(note["path"]), set())
        ]
        basename_counts: dict[str, int] = {}
        for note in notes:
            basename = str(note["basename"])
            basename_counts[basename] = basename_counts.get(basename, 0) + 1
        summary = {
            "indexed_notes": len(notes),
            "content_notes": sum(1 for note in notes if not note["is_moc"]),
            "mocs": sum(1 for note in notes if note["is_moc"]),
            "links": len(resolved_links),
            "resolved_links": sum(
                1 for link in resolved_links if link["resolution_status"] == "resolved"
            ),
            "dangling_links": len(dangling_links),
            "orphan_candidates": len(orphan_candidates),
            "warnings": len(warnings),
            "duplicate_basenames": sum(1 for count in basename_counts.values() if count > 1),
        }
        return {
            "vault": str(self.vault),
            "index": str(self.index_path),
            "exports": str(self.vault / EXPORT_REL),
            "summary": summary,
            "notes": notes,
            "links": resolved_links,
            "dangling_links": dangling_links,
            "orphan_candidates": orphan_candidates,
            "warnings": warnings,
        }

    def write_exports(self, formats: tuple[str, ...] = ("markdown", "csv")) -> dict[str, Any]:
        normalized = set(formats)
        if "all" in normalized:
            normalized.update({"markdown", "csv"})
        export_dir = self.vault / EXPORT_REL
        export_dir.mkdir(parents=True, exist_ok=True)
        payload = self.export()
        paths: list[Path] = []
        if "markdown" in normalized:
            paths.append(self.write_markdown_export(export_dir / "vault-index.md", payload))
        if "csv" in normalized:
            paths.extend(self.write_csv_exports(export_dir, payload))
        return {
            "summary": payload["summary"],
            "exports": [rel_id(path, self.vault) for path in paths],
        }

    def write_markdown_export(self, path: Path, payload: dict[str, Any]) -> Path:
        summary_rows = [
            {"metric": key, "value": value}
            for key, value in sorted(payload["summary"].items(), key=lambda item: item[0])
        ]
        note_rows = [
            {
                "path": note["path"],
                "basename": note["basename"],
                "title": note["title"],
                "type": note["note_type"],
                "moc": note["is_moc"],
                "description": note["description"],
            }
            for note in payload["notes"]
        ]
        link_rows = [
            {
                "source_path": link["source_path"],
                "ordinal": link["ordinal"],
                "target": link["target"],
                "status": link["resolution_status"],
                "resolved_path": link["resolved_path"],
            }
            for link in payload["links"]
        ]
        dangling_rows = [
            {
                "target": link["target"],
                "source_path": link["source_path"],
                "ordinal": link["ordinal"],
                "raw": link["raw"],
            }
            for link in payload["dangling_links"]
        ]
        warning_rows = [
            {"path": warning["path"], "message": warning["message"]}
            for warning in payload["warnings"]
        ]

        lines = ["# VaultIndex Export", ""]
        for heading, headers, rows in [
            ("Summary Metrics", ["metric", "value"], summary_rows),
            ("Notes", ["path", "basename", "title", "type", "moc", "description"], note_rows),
            ("Links", ["source_path", "ordinal", "target", "status", "resolved_path"], link_rows),
            ("Dangling Links", ["target", "source_path", "ordinal", "raw"], dangling_rows),
            (
                "Orphan Candidates",
                ["path", "basename", "title", "description"],
                payload["orphan_candidates"],
            ),
            ("Parse Warnings", ["path", "message"], warning_rows),
        ]:
            lines.append(f"## {heading}")
            lines.extend(markdown_table(headers, rows))
            lines.append("")
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
        return path

    def write_csv_exports(self, export_dir: Path, payload: dict[str, Any]) -> list[Path]:
        specs: list[tuple[str, list[str], list[dict[str, Any]]]] = [
            (
                "vault-index-summary.csv",
                ["metric", "value"],
                [
                    {"metric": key, "value": value}
                    for key, value in sorted(payload["summary"].items(), key=lambda item: item[0])
                ],
            ),
            (
                "vault-index-notes.csv",
                [
                    "path",
                    "basename",
                    "title",
                    "description",
                    "note_type",
                    "is_moc",
                    "aliases",
                    "topics",
                    "created",
                    "size",
                    "mtime_ns",
                    "content_hash",
                ],
                [
                    {
                        "path": note["path"],
                        "basename": note["basename"],
                        "title": note["title"],
                        "description": note["description"],
                        "note_type": note["note_type"],
                        "is_moc": note["is_moc"],
                        "aliases": note["aliases"],
                        "topics": note["topics"],
                        "created": note["created"],
                        "size": note["size"],
                        "mtime_ns": note["mtime_ns"],
                        "content_hash": note["content_hash"],
                    }
                    for note in payload["notes"]
                ],
            ),
            (
                "vault-index-links.csv",
                ["source_path", "ordinal", "target", "raw", "resolution_status", "resolved_path"],
                payload["links"],
            ),
            (
                "vault-index-dangling-links.csv",
                ["target", "source_path", "ordinal", "raw"],
                payload["dangling_links"],
            ),
            (
                "vault-index-orphan-candidates.csv",
                ["path", "basename", "title", "description"],
                payload["orphan_candidates"],
            ),
            (
                "vault-index-warnings.csv",
                ["path", "message"],
                payload["warnings"],
            ),
        ]
        paths = []
        for filename, fieldnames, rows in specs:
            path = export_dir / filename
            self.write_csv_file(path, fieldnames, rows)
            paths.append(path)
        return paths

    def write_csv_file(self, path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
            writer.writeheader()
            for row in rows:
                writer.writerow({field: csv_cell(row.get(field, "")) for field in fieldnames})


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


def print_export_result(result: dict[str, Any]) -> None:
    print("--=={ vault index exports }==--")
    for export_path in result["exports"]:
        print(f"generated: {export_path}")
    summary = result.get("summary", {})
    if summary:
        print(f"indexed_notes: {summary.get('indexed_notes', 0)}")
        print(f"dangling_links: {summary.get('dangling_links', 0)}")
        print(f"orphan_candidates: {summary.get('orphan_candidates', 0)}")
        print(f"warnings: {summary.get('warnings', 0)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="vault_index.py")
    parser.add_argument("command", choices=["build", "status", "export"])
    parser.add_argument("vault")
    parser.add_argument("--format", choices=["text", "json", "markdown", "csv", "all"], default="text")
    args = parser.parse_args(argv)
    if args.command != "export" and args.format not in {"text", "json"}:
        parser.error(f"--format {args.format} is only supported for export")
    index = VaultIndex(args.vault)
    if args.command == "export":
        if args.format == "json":
            print_payload(index.export(), "json")
            return 0
        formats = ("markdown", "csv") if args.format in {"text", "all"} else (args.format,)
        print_export_result(index.write_exports(formats))
        return 0
    payload = getattr(index, args.command)()
    print_payload(payload, args.format)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
