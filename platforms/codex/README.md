# Codex Platform Workflows

Codex does not currently expose a stable hook API equivalent to Claude Code
hooks. Ars Contexta therefore uses explicit Codex skills and deterministic
scripts for session rhythm instead of background automation.

## Claude Hook Translation

| Claude behavior | Codex workflow |
| --- | --- |
| `SessionStart` runs `session-orient.sh` automatically | Ask for `arscontexta-session orient` |
| `PostToolUse Write` runs lightweight validation | Ask for `arscontexta-session validate` with a file or changed set |
| Async auto-commit runs after writes | Review `git status` and make an intentional Conventional Commit |
| `Stop` or session capture hook writes handoff state | Ask for `arscontexta-session capture` with a summary |

Codex workflows are explicit on purpose. They keep session rhythm available
without depending on unstable background APIs or hidden transcript access.

## Session Modes

`arscontexta-session orient` is read-only. It summarizes vault marker state,
current goals or handoff files, queue pressure, inbox pressure, observation and
tension counts, and the latest health report when present.

`arscontexta-session validate` is warning-only. It checks the lightweight schema
signals Claude hooks used to catch after writes: frontmatter, `description:`,
`topics:`, and obvious unresolved wiki links.

`arscontexta-session capture` is explicit. Codex cannot automatically save a
complete transcript unless the user provides one or Codex later exposes a stable
transcript API. The capture workflow writes a markdown handoff into
`ops/sessions/` and updates `ops/sessions/current.md`.

## Automation Boundary

Do not add Codex cron jobs, background automations, or auto-commit behavior as a
hook replacement. If Codex later provides a stable hook API, add a new design
issue that maps these explicit workflows onto that API.

## Optional MCP

Codex skills may use Ars Contexta MCP tools when a compatible server exists, but
they must not require MCP. Prefer this order:

1. MCP tool, when installed and compatible.
2. Bundled deterministic script from `scripts/` or `plugins/arscontexta/scripts/`.
3. Local `rg`, `find`, and shell inspection.

The current MCP work is a CLI prototype, not a registered server:

```bash
scripts/mcp-vault-tools.sh links.check . --limit 25
scripts/mcp-vault-tools.sh frontmatter.validate . --changed --limit 25
```
