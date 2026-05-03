#!/usr/bin/env python3
"""Incremental SQLite index for Ars Contexta markdown vaults."""

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
            links = [
                dict(row)
                for row in conn.execute(
                    "SELECT source_path, target, raw FROM links ORDER BY source_path, target, raw"
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
