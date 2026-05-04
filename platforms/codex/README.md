# Codex Platform Workflows

HippocampusMD uses explicit Codex skills and deterministic scripts for session
rhythm, validation, queue work, and graph maintenance.

## Session Workflows

`hippocampusmd-session orient` is read-only. It summarizes vault marker state,
current goals or handoff files, queue pressure, inbox pressure, observation and
tension counts, and the latest health report when present.

`hippocampusmd-session validate` is warning-only. It checks lightweight schema
signals after edits: frontmatter, `description:`, `topics:`, and obvious
unresolved wiki links.

`hippocampusmd-session capture` is explicit. It writes a markdown handoff into
`ops/sessions/` and updates `ops/sessions/current.md`.

## Automation Boundary

Do not add background automations or auto-commit behavior as a replacement for
explicit Codex workflows. If Codex later provides a stable automation interface,
add a design issue before wiring it into HippocampusMD.

## Optional Search Tooling

Codex skills may use compatible search tools when available, but they must not
require them. Prefer this order:

1. Bundled deterministic script from `plugins/hippocampusmd/scripts/`.
2. Local `rg`, `find`, and shell inspection.
3. Optional indexed or semantic search tooling when the user has installed it.
