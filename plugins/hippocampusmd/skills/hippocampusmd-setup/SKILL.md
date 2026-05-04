---
name: hippocampusmd-setup
description: Use when the user asks Codex to set up, initialize, scaffold, or adapt a HippocampusMD vault.
---

# HippocampusMD Setup

Create or complete a Codex-native HippocampusMD vault. It writes durable scaffolding, `AGENTS.md`, and explicit session workflow guidance.

## When Invoked

1. Treat the current working directory as the target vault unless the user gives another path.
2. Detect context before writing:
   - Plugin repo: `.agents/plugins/marketplace.json` or `plugins/hippocampusmd/.codex-plugin/plugin.json` exists. Do not set up the repo as a vault.
   - Existing HippocampusMD vault: `.hippocampusmd` exists. Report what exists and fill missing minimal files only after explicit approval.
   - Existing markdown vault: markdown files or vault-like directories exist but `.hippocampusmd` is absent. Explain that setup will add scaffolding without moving notes.
   - Empty directory: safe setup target.
   - Generic non-empty directory: warn and require explicit confirmation before writing.
3. Ask only the minimum needed before writes:
   - domain/use case name
   - preset: `research`, `personal`, or `experimental`
   - confirmation to write files

Infer a preset when obvious:

- research papers, claims, literature, technical notes -> `research`
- reflections, goals, relationships, life tracking -> `personal`
- unusual domain, custom design, unsure fit -> `experimental`

## Write Path

Prefer the deterministic helper:

```bash
plugins/hippocampusmd/scripts/setup-vault.sh . --preset research --domain "my domain"
```

From an installed plugin package or the repository, discover the helper relative to the plugin root:

```bash
plugins/hippocampusmd/scripts/setup-vault.sh . --preset research --domain "my domain"
```

Use `--dry-run` first when the target is non-empty or already has markdown files.

The helper creates missing files only. It must not overwrite `AGENTS.md`, user notes, templates, or config files.

## Generated Scope

Minimal Codex setup creates:

- `.hippocampusmd`
- `AGENTS.md`
- `notes/`, `inbox/`, `archive/`, `self/`, `manual/`, `templates/`, `ops/`
- `ops/derivation.md`
- `ops/derivation-manifest.md`
- `ops/config.yaml`
- `ops/queue/`, `ops/health/`, `ops/observations/`, `ops/tensions/`, `ops/sessions/`, `ops/methodology/`
- base note and MOC templates
- starter MOCs for the selected preset
- `manual/manual.md`, `manual/getting-started.md`, `manual/skills.md`

The helper reads bundled plugin source assets from `plugins/hippocampusmd/presets/`
and `plugins/hippocampusmd/generators/`, but generated vaults must not receive
those source directories. Vaults receive only derived files and the local
`ops/methodology/` self-knowledge space.

## Platform Rules

- Generate `AGENTS.md` for Codex.
- Do not install hidden background hooks, generated legacy templates, or MCP config.
- Emphasize explicit Codex workflows, local file reads, and approved writes.
- After setup, recommend `scripts/check-vault.sh <vault-path>` and `hippocampusmd-health`.

## Response Rules

- Before writing, summarize the target path, inferred preset, domain name, and files that will be created.
- After writing, report created vs existing files at a high level and give one next action.
- Do not run broad health diagnostics during setup; leave that to `hippocampusmd-health`.
- Keep setup language Codex-native. Use plugin skill names and explicit user intent.
