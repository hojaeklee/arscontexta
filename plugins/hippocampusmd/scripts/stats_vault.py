#!/usr/bin/env python3
"""Read-only HippocampusMD vault statistics."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import datetime as dt
import json
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any

from vault_index import SCHEMA_VERSION, VaultIndex, rel_id, scan_markdown_files, split_frontmatter

WIKI_RE = re.compile(r"\[\[([^\]]+)\]\]")


class StatsFallback(Exception):
    """Raised when indexed stats cannot be used and direct scan should run."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="stats-vault.sh",
        usage="%(prog)s [vault-path] [--share] [--limit N] [--format text|json]",
        add_help=False,
    )
    parser.add_argument("vault", nargs="?", default=".")
    parser.add_argument("--share", action="store_true")
    parser.add_argument("--limit", type=int, default=25)
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("-h", "--help", action="help")
    args = parser.parse_args(argv)
    if args.limit < 0:
        parser.error("Limit must be a non-negative integer.")
    return args


def relpath(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [item.strip().strip('"').strip("'") for item in inner.split(",") if item.strip()]
    return value.strip('"').strip("'")


def parse_simple_yaml(text: str) -> dict[str, Any]:
    data: dict[str, Any] = {}
    current_key = ""
    current_list_key = ""
    for raw_line in text.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()
        if indent == 0 and ":" in line:
            key, raw_value = line.split(":", 1)
            key = key.strip()
            value = raw_value.strip()
            if value:
                data[key] = parse_scalar(value)
                current_key = ""
            else:
                data[key] = {}
                current_key = key
            current_list_key = ""
            continue
        if indent >= 2 and current_key and ":" in line:
            key, raw_value = line.split(":", 1)
            key = key.strip()
            value = raw_value.strip()
            parent = data.setdefault(current_key, {})
            if isinstance(parent, dict):
                parent[key] = parse_scalar(value) if value else []
                current_list_key = key if not value else ""
            continue
        if indent >= 2 and line.startswith("- ") and current_key and current_list_key:
            parent = data.setdefault(current_key, {})
            if isinstance(parent, dict):
                parent.setdefault(current_list_key, []).append(parse_scalar(line[2:].strip()))
    return data


def safe_load_yaml_document(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"\A(?:#.*\n|\s*\n)*---\n(.*?)\n---", text, re.M | re.S)
    yaml_text = match.group(1) if match else text
    loaded = parse_simple_yaml(yaml_text)
    return loaded if isinstance(loaded, dict) else {}


def vocabulary(root: Path) -> dict[str, str]:
    manifest = safe_load_yaml_document(root / "ops/derivation-manifest.md")
    config = safe_load_yaml_document(root / "ops/config.yaml")
    vocab = manifest.get("vocabulary", {})
    if not isinstance(vocab, dict):
        vocab = {}
    note = str(vocab.get("note") or "note")
    return {
        "notes": str(vocab.get("notes") or config.get("notes_dir") or "notes"),
        "inbox": str(vocab.get("inbox") or config.get("inbox_dir") or "inbox"),
        "note": note,
        "note_plural": str(vocab.get("note_plural") or f"{note}s"),
        "topic_map": str(vocab.get("topic_map") or "topic map"),
        "topic_map_plural": str(vocab.get("topic_map_plural") or "topic maps"),
        "reflect": str(vocab.get("cmd_reflect") or vocab.get("reflect") or "reflect"),
        "rethink": str(vocab.get("rethink") or vocab.get("cmd_rethink") or "rethink"),
    }


def markdown_files(root: Path, rel_dir: str) -> list[Path]:
    directory = root / rel_dir
    if not directory.is_dir():
        return []
    return sorted(directory.glob("**/*.md"))


def count_files(root: Path, rel_dir: str) -> int:
    directory = root / rel_dir
    if not directory.is_dir():
        return 0
    return len(list(directory.glob("*.md")))


def frontmatter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    data, _body, _warnings = split_frontmatter(text)
    return data if isinstance(data, dict) else {}


def wiki_link_targets(text: str) -> list[str]:
    links: list[str] = []
    for raw in WIKI_RE.findall(text):
        target = raw.split("|", 1)[0].split("#", 1)[0].strip()
        if target:
            links.append(target)
    return links


def normalize_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        parsed = parse_scalar(value)
        if isinstance(parsed, list):
            return normalize_list(parsed)
        return [value.strip()]
    return []


def pct(numerator: int, denominator: int) -> int | None:
    if denominator <= 0:
        return None
    return round((numerator * 100.0) / denominator)


def decimal(numerator: int, denominator: int, places: int = 2) -> float | None:
    if denominator <= 0:
        return None
    return round(numerator / denominator, places)


def oldest_age_days(files: list[Path]) -> int | None:
    if not files:
        return None
    oldest = min(files, key=lambda path: path.stat().st_mtime)
    return int((time.time() - oldest.stat().st_mtime) // 86_400)


def created_this_week(value: Any) -> bool:
    if not value:
        return False
    if isinstance(value, dt.date):
        date = value
    else:
        try:
            date = dt.date.fromisoformat(str(value)[:10])
        except ValueError:
            return False
    return date >= dt.date.today() - dt.timedelta(days=7)


def queue_file(root: Path) -> str | None:
    for rel in ["ops/queue/queue.json", "ops/queue/queue.yaml", "ops/queue.yaml"]:
        if (root / rel).is_file():
            return rel
    return None


def normalize_status(status: Any) -> str:
    value = str(status or "").lower()
    if value in {"pending", "todo", "queued"}:
        return "pending"
    if value in {"active", "in_progress", "in-progress", "running", "current"}:
        return "active"
    if value in {"done", "completed", "complete"}:
        return "completed"
    if value in {"blocked", "waiting"}:
        return "blocked"
    return "unknown" if not value else value


def parse_queue_yaml(text: str) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    in_tasks = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "tasks:":
            in_tasks = True
            continue
        if not in_tasks:
            continue
        if line.startswith("- "):
            if current:
                tasks.append(current)
            current = {}
            line = line[2:].strip()
            if ":" in line:
                key, value = line.split(":", 1)
                current[key.strip()] = parse_scalar(value.strip())
            continue
        if current is not None and ":" in line:
            key, value = line.split(":", 1)
            current[key.strip()] = parse_scalar(value.strip())
    if current:
        tasks.append(current)
    return tasks


def queue_tasks_from_data(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, dict) and isinstance(data.get("tasks"), list):
        raw = data["tasks"]
    elif isinstance(data, list):
        raw = data
    elif isinstance(data, dict):
        raw = next((value for value in data.values() if isinstance(value, list)), [])
    else:
        raw = []
    return [entry for entry in raw if isinstance(entry, dict)]


def parse_queue(root: Path) -> dict[str, Any]:
    rel = queue_file(root)
    if not rel:
        return {"exists": False, "file": None, "counts": Counter()}
    path = root / rel
    try:
        if rel.endswith(".json"):
            tasks = queue_tasks_from_data(json.loads(path.read_text(encoding="utf-8")))
        else:
            tasks = parse_queue_yaml(path.read_text(encoding="utf-8", errors="replace"))
        counts = Counter(normalize_status(task.get("status")) for task in tasks)
        return {"exists": True, "file": rel, "counts": counts}
    except (OSError, json.JSONDecodeError) as exc:
        return {"exists": True, "file": rel, "counts": Counter(), "error": str(exc)}


def pending_status_count(root: Path, rel_dir: str, statuses: list[str]) -> int:
    wanted = {status.lower() for status in statuses}
    count = 0
    for path in markdown_files(root, rel_dir):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            if key.strip().lower() == "status" and value.strip().lower() in wanted:
                count += 1
                break
    return count


def add_unique(mapping: dict[str, set[str]], key: str, path: str) -> None:
    key = key.strip()
    if key:
        mapping[key].add(path)


def note_title(path: Path) -> str:
    return path.stem


def title_from_markdown(path: Path, metadata: dict[str, Any]) -> str:
    title = str(metadata.get("title", "")).strip()
    if title:
        return title
    text = path.read_text(encoding="utf-8", errors="replace")
    _frontmatter, body, _warnings = split_frontmatter(text)
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def build_target_lookup(note_entries: list[dict[str, Any]]) -> dict[str, set[str]]:
    lookup: dict[str, set[str]] = defaultdict(set)
    for entry in note_entries:
        path = str(entry["path"])
        path_no_suffix = path[:-3] if path.endswith(".md") else path
        add_unique(lookup, path, path)
        add_unique(lookup, path_no_suffix, path)
        add_unique(lookup, str(entry.get("basename", "")), path)
        add_unique(lookup, str(entry.get("title", "")), path)
        for alias in normalize_list(entry.get("aliases", [])):
            add_unique(lookup, alias, path)
    return lookup


def resolve_target(target: str, lookup: dict[str, set[str]]) -> tuple[str, str | None]:
    normalized = target[:-3] if target.endswith(".md") else target
    matches = lookup.get(normalized) or lookup.get(target) or set()
    if len(matches) == 1:
        return "resolved", next(iter(matches))
    if len(matches) > 1:
        return "ambiguous", None
    return "missing", None


def topic_link_count(topics: Any) -> int:
    return len(set(wiki_link_targets(str(topics))))


def compute_graph_metrics(note_entries: list[dict[str, Any]], links_by_file: dict[str, list[str]]) -> dict[str, Any]:
    moc_files = [entry for entry in note_entries if bool(entry.get("is_moc"))]
    content_files = [entry for entry in note_entries if not bool(entry.get("is_moc"))]
    all_links = [target for links in links_by_file.values() for target in links]
    lookup = build_target_lookup(note_entries)
    incoming = Counter()
    dangling_targets: set[str] = set()
    for links in links_by_file.values():
        for target in links:
            status, resolved = resolve_target(target, lookup)
            if status == "resolved" and resolved:
                incoming[resolved] += 1
            elif status == "missing":
                dangling_targets.add(target)

    large_vault = len(note_entries) > 200
    orphans = sum(1 for entry in content_files if incoming[str(entry["path"])] == 0)
    missing_desc = sum(1 for entry in note_entries if not str(entry.get("description", "")).strip())
    missing_topics = sum(1 for entry in note_entries if not normalize_list(entry.get("topics", [])))
    topic_links: set[str] = set()
    for entry in note_entries:
        topic_links.update(wiki_link_targets(str(entry.get("topics", []))))
    covered = sum(1 for entry in content_files if normalize_list(entry.get("topics", [])))
    this_week_entries = [entry for entry in content_files if created_this_week(entry.get("created"))]
    return {
        "total_files": len(note_entries),
        "notes": len(content_files),
        "mocs": len(moc_files),
        "connections": len(all_links),
        "avg_links": decimal(len(all_links), max(len(content_files), 1), 1) or 0,
        "density": decimal(len(all_links), len(content_files) * max(len(content_files) - 1, 1), 4),
        "topics": len(topic_links),
        "moc_coverage": pct(covered, len(content_files)),
        "orphans": orphans,
        "dangling": len(dangling_targets),
        "schema_compliance": pct(len(note_entries) - max(missing_desc, missing_topics), len(note_entries)),
        "missing_description": missing_desc,
        "missing_topics": missing_topics,
        "this_week_notes": len(this_week_entries),
        "this_week_links": sum(len(links_by_file[str(entry["path"])]) for entry in this_week_entries),
        "large_vault_approximate": large_vault,
    }


def direct_graph_metrics(vault: Path, notes_dir: str) -> dict[str, Any]:
    note_files = markdown_files(vault, notes_dir)
    metadata = {path: frontmatter(path) for path in note_files}
    entries: list[dict[str, Any]] = []
    links_by_file: dict[str, list[str]] = {}
    for path in note_files:
        data = metadata[path]
        rel = relpath(path, vault)
        entries.append(
            {
                "path": rel,
                "basename": path.stem,
                "title": title_from_markdown(path, data),
                "aliases": normalize_list(data.get("aliases", [])),
                "description": str(data.get("description", "")).strip(),
                "is_moc": str(data.get("type", "")).lower() == "moc",
                "topics": normalize_list(data.get("topics", [])),
                "created": data.get("created", ""),
            }
        )
        links_by_file[rel] = wiki_link_targets(path.read_text(encoding="utf-8", errors="replace"))
    return compute_graph_metrics(entries, links_by_file)


def indexed_graph_metrics(vault: Path, notes_dir: str) -> dict[str, Any]:
    index = VaultIndex(vault)
    try:
        scan = scan_markdown_files(vault)
        current = {rel_id(path, vault): path for path in scan.files}
        with index.connect_readonly() as conn:
            schema_row = conn.execute("SELECT value FROM meta WHERE key = 'schema_version'").fetchone()
            if not schema_row or schema_row["value"] != SCHEMA_VERSION:
                raise StatsFallback("VaultIndex schema is stale; falling back to direct scan. Run hippocampusmd-index to rebuild.")
            rows = [dict(row) for row in conn.execute("SELECT * FROM notes ORDER BY path")]
            indexed_paths = {str(row["path"]) for row in rows}
            if indexed_paths != set(current):
                raise StatsFallback("VaultIndex is stale; falling back to direct scan. Run hippocampusmd-index to rebuild.")
            for row in rows:
                stat = current[str(row["path"])].stat()
                if int(row["mtime_ns"]) != stat.st_mtime_ns or int(row["size"]) != stat.st_size:
                    raise StatsFallback("VaultIndex is stale; falling back to direct scan. Run hippocampusmd-index to rebuild.")
            links = [dict(row) for row in conn.execute("SELECT source_path, target FROM links ORDER BY source_path, ordinal")]
    except FileNotFoundError:
        raise StatsFallback("VaultIndex is missing; falling back to direct scan. Run hippocampusmd-index to build it.")
    except sqlite3.Error as exc:
        raise StatsFallback(f"VaultIndex is unreadable ({exc}); falling back to direct scan.")

    prefix = notes_dir.rstrip("/") + "/"
    note_entries: list[dict[str, Any]] = []
    note_paths: set[str] = set()
    for row in rows:
        path = str(row["path"])
        if not path.startswith(prefix) or not path.endswith(".md"):
            continue
        note_paths.add(path)
        note_entries.append(
            {
                "path": path,
                "basename": row["basename"],
                "title": row["title"],
                "aliases": json.loads(row["aliases_json"]),
                "description": row["description"],
                "is_moc": bool(row["is_moc"]),
                "topics": json.loads(row["topics_json"]),
                "created": row["created"],
            }
        )
    links_by_file: dict[str, list[str]] = {path: [] for path in note_paths}
    for link in links:
        source = str(link["source_path"])
        if source in links_by_file:
            links_by_file[source].append(str(link["target"]))
    return compute_graph_metrics(note_entries, links_by_file)


def system_metrics(vault: Path, vocab: dict[str, str], graph_metrics: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    inbox_files = markdown_files(vault, vocab["inbox"])
    queue = parse_queue(vault)
    content_count = int(graph_metrics["notes"])
    processed_pct = pct(content_count, content_count + len(inbox_files))
    self_files = count_files(vault, "self")
    health_reports = count_files(vault, "ops/health")
    health_files = sorted((vault / "ops/health").glob("*.md")) if (vault / "ops/health").is_dir() else []
    latest_health = relpath(health_files[-1], vault) if health_files else None
    metrics = {
        **graph_metrics,
        "inbox": len(inbox_files),
        "oldest_inbox_age_days": oldest_age_days(inbox_files),
        "queue_pending": queue["counts"]["pending"],
        "queue_done": queue["counts"]["completed"],
        "queue_blocked": queue["counts"]["blocked"],
        "processed_pct": processed_pct,
        "self_space": f"enabled ({self_files} files)" if self_files > 0 else "disabled",
        "methodology": count_files(vault, "ops/methodology"),
        "observations_pending": pending_status_count(vault, "ops/observations", ["pending"]),
        "tensions_pending": pending_status_count(vault, "ops/tensions", ["pending", "open"]),
        "sessions": count_files(vault, "ops/sessions"),
        "health_reports": health_reports,
        "latest_health": latest_health,
    }
    return metrics, queue


def interpretation_notes(metrics: dict[str, Any], vocab: dict[str, str]) -> list[str]:
    notes: list[str] = []
    if metrics["orphans"] > 0:
        notes.append(f"{metrics['orphans']} orphan {vocab['note_plural']} -- run hippocampusmd-graph for details")
    if metrics["dangling"] > 0:
        notes.append(f"{metrics['dangling']} dangling links -- run hippocampusmd-graph to identify broken links")
    if metrics["schema_compliance"] is not None and metrics["schema_compliance"] < 90:
        notes.append(f"Schema compliance below 90% -- some {vocab['note_plural']} are missing required fields")
    if metrics["observations_pending"] >= 10:
        notes.append(f"{metrics['observations_pending']} pending observations -- consider {vocab['rethink']}")
    if metrics["tensions_pending"] >= 5:
        notes.append(f"{metrics['tensions_pending']} open tensions -- consider {vocab['rethink']}")
    if metrics["density"] is not None and metrics["density"] < 0.02 and metrics["notes"] > 5:
        notes.append(f"Graph density is low -- run {vocab['reflect']} to strengthen the network")
    if metrics["processed_pct"] is not None and metrics["processed_pct"] < 50:
        notes.append(f"More content in inbox than in {vocab['notes']}/ -- consider processing backlog")
    if metrics["total_files"] > 0 and metrics["this_week_notes"] == 0:
        notes.append(f"No new {vocab['note_plural']} this week")
    if metrics["large_vault_approximate"]:
        notes.append("Metrics approximate for large vault. Run hippocampusmd-graph for precise graph analysis.")
    return notes


def render_json(vault: Path, vocab: dict[str, str], queue: dict[str, Any], metrics: dict[str, Any], notes: list[str]) -> None:
    print(
        json.dumps(
            {
                "vault": str(vault),
                "vocabulary": vocab,
                "queue_file": queue["file"],
                "metrics": metrics,
                "notes": notes,
            },
            indent=2,
        )
    )


def render_share(metrics: dict[str, Any], vocab: dict[str, str]) -> None:
    print("## My Knowledge Graph")
    print()
    print(
        f"- **{metrics['notes']}** {vocab['note_plural']} with **{metrics['connections']}** connections "
        f"(avg {metrics['avg_links']} per {vocab['note']})"
    )
    print(
        f"- **{metrics['mocs']}** {vocab['topic_map_plural']} covering "
        f"{metrics['moc_coverage'] if metrics['moc_coverage'] is not None else 'N/A'}% of {vocab['note_plural']}"
    )
    print(f"- Schema compliance: {metrics['schema_compliance'] if metrics['schema_compliance'] is not None else 'N/A'}%")
    print(f"- This week: +{metrics['this_week_notes']} {vocab['note_plural']}, +{metrics['this_week_links']} connections")
    print(f"- Graph density: {metrics['density'] if metrics['density'] is not None else 'N/A'}")
    print()
    print("*Built with HippocampusMD*")


def progress_bar(value: int | None) -> str:
    bar_pct = value or 0
    filled = max(0, min(bar_pct // 5, 20))
    return f"[{'=' * filled}{' ' * (20 - filled)}] {bar_pct}%"


def render_text(metrics: dict[str, Any], vocab: dict[str, str], queue: dict[str, Any], notes: list[str], limit: int) -> None:
    if metrics["total_files"] == 0:
        print("--=={ stats }==--")
        print()
        print("Your knowledge graph is new. Start capturing to see it grow.")
        print()
        print("Knowledge Graph")
        print("===============")
        print(f"{vocab['note_plural']}: 0")
        print("Connections: 0")
        print(f"{vocab['topic_map_plural']}: 0")
        print("Topics: 0")
        print()
        print("Generated by HippocampusMD")
        return

    print("--=={ stats }==--")
    print()
    print("Knowledge Graph")
    print("===============")
    print(f"{vocab['note_plural']}: {metrics['notes']}")
    print(f"Connections: {metrics['connections']} (avg {metrics['avg_links']} per {vocab['note']})")
    coverage = metrics["moc_coverage"] if metrics["moc_coverage"] is not None else "N/A"
    print(f"{vocab['topic_map_plural']}: {metrics['mocs']} (covering {coverage}% of {vocab['note_plural']})")
    print(f"Topics: {metrics['topics']}")
    print()
    print("Health")
    print("======")
    print(f"Orphans: {metrics['orphans']}")
    print(f"Dangling: {metrics['dangling']}")
    schema = metrics["schema_compliance"] if metrics["schema_compliance"] is not None else "N/A"
    print(f"Schema: {schema}% compliant")
    print()
    if queue["exists"] or metrics["inbox"] > 0:
        print("Pipeline")
        print("========")
        print(f"Processed: {progress_bar(metrics['processed_pct'])}")
        oldest = f" (oldest {metrics['oldest_inbox_age_days']}d)" if metrics["oldest_inbox_age_days"] is not None else ""
        print(f"Inbox: {metrics['inbox']} items{oldest}")
        if queue["exists"]:
            print(f"Queue: {metrics['queue_pending']} pending, {metrics['queue_blocked']} blocked, {metrics['queue_done']} done")
        print()
    print("Growth")
    print("======")
    print(f"This week: +{metrics['this_week_notes']} {vocab['note_plural']}, +{metrics['this_week_links']} connections")
    print(f"Graph density: {metrics['density'] if metrics['density'] is not None else 'N/A'}")
    print()
    print("System")
    print("======")
    print(f"Self space: {metrics['self_space']}")
    print(f"Methodology: {metrics['methodology']} learned patterns")
    print(f"Observations: {metrics['observations_pending']} pending")
    print(f"Tensions: {metrics['tensions_pending']} open")
    print(f"Sessions: {metrics['sessions']} captured")
    latest = f" (latest {metrics['latest_health']})" if metrics["latest_health"] else ""
    print(f"Health reports: {metrics['health_reports']}{latest}")
    print()
    if notes:
        print("Notes")
        print("=====")
        for note in notes[:limit]:
            print(f"- {note}")


def run(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    vault = Path(args.vault).expanduser().resolve()
    if not vault.is_dir():
        print(f"Vault path is not a directory: {args.vault}", file=sys.stderr)
        return 2
    vocab = vocabulary(vault)
    try:
        graph_metrics = indexed_graph_metrics(vault, vocab["notes"])
    except StatsFallback as exc:
        print(str(exc), file=sys.stderr)
        graph_metrics = direct_graph_metrics(vault, vocab["notes"])
    metrics, queue = system_metrics(vault, vocab, graph_metrics)
    notes = interpretation_notes(metrics, vocab)

    if args.format == "json":
        render_json(vault, vocab, queue, metrics, notes)
    elif args.share:
        render_share(metrics, vocab)
    else:
        render_text(metrics, vocab, queue, notes, args.limit)
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
