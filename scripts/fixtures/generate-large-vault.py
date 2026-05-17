#!/usr/bin/env python3
"""Generate deterministic large HippocampusMD vault fixtures for tests."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be non-negative")
    return parsed


def note_frontmatter(title: str, note_type: str, aliases: list[str]) -> str:
    alias_lines = "\n".join(f"  - {alias}" for alias in aliases)
    return "\n".join(
        [
            "---",
            f"description: {title} fixture note for large-vault command tests",
            f"type: {note_type}",
            "topics: [\"[[index]]\"]",
            "aliases:",
            alias_lines,
            "created: 2026-05-03",
            "---",
            "",
        ]
    )


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def regular_note(index: int, total_regular: int, aliases_per_note: int) -> str:
    title = f"Note {index:04d}"
    aliases = [
        f"alias-{index:04d}-{alias_index:02d}" for alias_index in range(aliases_per_note)
    ]
    next_index = (index + 1) % max(total_regular, 1)
    previous_index = (index - 1) % max(total_regular, 1)
    links = [
        f"[[Note {next_index:04d}]]",
        f"[[Note {previous_index:04d}]]",
        "[[index]]",
    ]
    return (
        note_frontmatter(title, "claim", aliases)
        + f"# {title}\n\n"
        + f"{title} links to {', '.join(links)}.\n"
    )


def duplicate_note(index: int) -> str:
    title = f"Duplicate {index}"
    return (
        note_frontmatter(title, "claim", [f"duplicate-alias-{index}"])
        + f"# {title}\n\n"
        + "This duplicate basename fixture links to [[index]] and [[Note 0000]].\n"
    )


def map_note(dense_moc_links: int, total_regular: int, duplicate_basenames: int) -> str:
    note_links = [f"[[Note {index:04d}]]" for index in range(min(dense_moc_links, total_regular))]
    duplicate_links = [f"[[Duplicate {index}]]" for index in range(duplicate_basenames)]
    body_links = note_links + duplicate_links + ["[[high-link-hub]]"]
    return (
        note_frontmatter("index", "moc", ["large vault index"])
        + "# index\n\n"
        + "Dense fixture map links to "
        + ", ".join(body_links)
        + ".\n"
    )


def high_link_hub(high_link_count: int, total_regular: int) -> str:
    links = [f"[[Note {index:04d}]]" for index in range(min(high_link_count, total_regular))]
    return (
        note_frontmatter("high-link-hub", "claim", ["dense link hub"])
        + "# high-link-hub\n\n"
        + "High-link fixture hub links to "
        + ", ".join(links)
        + ".\n"
    )


def write_ignored_files(vault: Path, folder: str, prefix: str, count: int) -> None:
    for index in range(count):
        write_text(
            vault / folder / f"{prefix}-{index:03d}.md",
            f"# Ignored {folder} {index:03d}\n\nThis file should not be indexed.\n",
        )


def write_config(vault: Path) -> None:
    write_text(
        vault / "ops/config.yaml",
        "\n".join(
            [
                "scan:",
                "  include:",
                "    - notes/**",
                "  exclude:",
                "    - archive/**",
                "    - imported/**",
                "    - attachments/**",
                "",
            ]
        ),
    )


def write_budgets(vault: Path, args: argparse.Namespace) -> None:
    budgets = {
        "fixture_notes": args.notes,
        "index_build_seconds": 8,
        "index_rescan_seconds": 2,
        "index_rescan_expected_scanned": 0,
        "index_rescan_expected_skipped": args.notes,
        "stats_seconds": 3,
        "graph_neighborhood_seconds": 3,
        "health_quick_seconds": 3,
        "validate_changed_seconds": 3,
    }
    write_text(
        vault / "ops/cache/performance-budgets.json",
        json.dumps(budgets, indent=2, sort_keys=True) + "\n",
    )


def generate(vault: Path, args: argparse.Namespace) -> None:
    fixed_notes = 2 + args.duplicate_basenames
    if args.notes < fixed_notes:
        raise ValueError(f"--notes must be at least {fixed_notes}")

    write_config(vault)
    regular_count = args.notes - fixed_notes
    for index in range(regular_count):
        shard = f"cluster-{index // 100:03d}"
        write_text(
            vault / "notes" / shard / f"note-{index:04d}.md",
            regular_note(index, regular_count, args.aliases_per_note),
        )

    for index in range(args.duplicate_basenames):
        write_text(
            vault / "notes" / "dupes" / f"group-{index:02d}" / "duplicate.md",
            duplicate_note(index),
        )

    write_text(
        vault / "notes/maps/index.md",
        map_note(args.dense_moc_links, regular_count, args.duplicate_basenames),
    )
    write_text(vault / "notes/high-link-hub.md", high_link_hub(args.high_link_count, regular_count))

    write_ignored_files(vault, "imported", "source", args.imported_files)
    write_ignored_files(vault, "archive", "old", args.archive_files)
    write_ignored_files(vault, "attachments", "file", args.attachment_files)
    write_budgets(vault, args)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="generate-large-vault.py")
    parser.add_argument("vault", type=Path)
    parser.add_argument("--notes", type=positive_int, default=1000)
    parser.add_argument("--aliases-per-note", type=positive_int, default=2)
    parser.add_argument("--duplicate-basenames", type=positive_int, default=4)
    parser.add_argument("--dense-moc-links", type=positive_int, default=100)
    parser.add_argument("--high-link-count", type=positive_int, default=75)
    parser.add_argument("--imported-files", type=positive_int, default=10)
    parser.add_argument("--archive-files", type=positive_int, default=10)
    parser.add_argument("--attachment-files", type=positive_int, default=5)
    args = parser.parse_args(argv)

    generate(args.vault.expanduser().resolve(), args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
