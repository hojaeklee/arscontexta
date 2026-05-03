# Ars Contexta

**Agent-native knowledge-system architecture for local markdown vaults.**

Ars Contexta helps Codex maintain a durable thinking system: plain markdown
notes, wiki links, processing queues, operational memory, and
Obsidian-friendly navigation.

**v0.8.5** | Codex-only local plugin | MIT

Codex is the only supported Ars Contexta distribution in this repo.
Claude Code support, hooks, slash commands, and legacy generated skill templates have been removed.

## What It Does

Most agent sessions start blank. Ars Contexta gives Codex a local memory
architecture it can inspect and maintain across sessions.

You get:

- A markdown vault connected by wiki links.
- A three-space architecture: `self/`, domain notes, and `ops/`.
- Processing workflows for capture, reduction, reflection, reweaving, and verification.
- Templates and schema conventions for consistent notes.
- Maintenance checks for links, frontmatter, orphans, queues, and drift.
- A methodology graph that explains why the system is shaped this way.

The core idea is **derivation, not templating**. A vault should be shaped by how
the user thinks and works, while still preserving stable operating principles.

## Use With Codex

Codex support is installed through a local marketplace entry in this repo:

```text
.agents/plugins/marketplace.json
plugins/arscontexta/.codex-plugin/plugin.json
plugins/arscontexta/skills/
plugins/arscontexta/scripts/
```

Add this marketplace to `~/.codex/config.toml`:

```toml
[marketplaces.agenticnotetaking]
source_type = "local"
source = "/Users/hlee/Desktop/playgrounds/arscontexta"

[plugins."arscontexta@agenticnotetaking"]
enabled = true
```

Then open Codex, go to **Codex Plugins** in the left sidebar, open the
**Agentic Note Taking** marketplace, and install or enable **Ars Contexta**.
Start a fresh chat after installing.

## Supported Skills

The installable Codex plugin includes skills for setup, help, health,
validation, session workflows, queue processing, graph diagnostics, note
extraction, reflection, evolution, recommendations, tutorial onboarding, and
research capture.

Typical prompts:

```text
What can Ars Contexta do here?
Run an Ars Contexta health check on this vault.
Set up Ars Contexta here for my research notes.
Use arscontexta-pipeline to plan this source.
Use arscontexta-session to capture a handoff.
```

Codex session workflows are explicit. They do not auto-commit or run in the
background.

## Repository Layout

```text
arscontexta/
|-- .agents/plugins/marketplace.json       # Codex local marketplace
|-- plugins/arscontexta/                   # Installable Codex plugin package
|   |-- .codex-plugin/plugin.json
|   |-- agents/                            # Bundled agent guidance definitions
|   |-- generators/                        # Bundled context and feature generators
|   |-- methodology/                       # Bundled research claims and methodology notes
|   |-- presets/                           # Bundled preset configs and starter notes
|   |-- reference/                         # Bundled references, templates, and fixtures
|   |-- scripts/
|   +-- skills/
|-- platforms/codex/                       # Codex workflow notes
|-- scripts/                               # Repo-level utility and test scripts
+-- README.md
```

plugins/arscontexta/ is the source of truth for the runtime plugin. Edit
plugin metadata, Codex-native skills, bundled scripts, agents, generators,
presets, and bundled knowledge there. The plugin-side
`plugins/arscontexta/agents/`, `plugins/arscontexta/generators/`,
`plugins/arscontexta/presets/`, `plugins/arscontexta/methodology/`, and
`plugins/arscontexta/reference/` directories are not copied into user vaults;
setup creates only derived vault artifacts and the vault-local
`ops/methodology/` self-knowledge space.

## Maintainer Workflow

### Local Git Identity

This repo should commit as the personal GitHub account:

```text
Hojae Lee <43919952+hojaeklee@users.noreply.github.com>
```

Check with:

```bash
git config --get user.name
git config --get user.email
```

### Remotes

`origin` should point at the personal fork through the personal SSH alias:

```text
origin git@github-hojaeklee:hojaeklee/arscontexta.git
```

`upstream` is fetch-only:

```text
upstream git@github.com:agenticnotetaking/arscontexta.git (fetch)
upstream DISABLED (push)
```

This prevents accidental pushes to the original repository.

### Updating The Codex Plugin

For Codex, treat the installable package as the source of truth. Edit:

```text
plugins/arscontexta/.codex-plugin/plugin.json
plugins/arscontexta/skills/<skill-name>/SKILL.md
plugins/arscontexta/scripts/
```

After editing:

```bash
scripts/check-codex-plugin.sh
scripts/tests/test-codex-smoke.sh
git status --short
```

Restart Codex before testing plugin discovery. Existing chats do not reliably
hot-reload plugin skills.

### When Codex Updates

Treat Codex app/runtime updates as compatibility events. After each update, run:

```bash
scripts/check-codex-plugin.sh
scripts/check-vault.sh "/path/to/vault"
```

Then confirm the Codex UI state that scripts cannot inspect directly:

1. Open the **Codex Plugins** sidebar and confirm **Agentic Note Taking** still appears.
2. Confirm **Ars Contexta** is still installed or enabled.
3. Start a fresh chat in this repo and verify Ars Contexta skills are available.
4. Start a fresh chat in a real vault and run an Ars Contexta health check.

Keep update fixes small and documented. If a Codex update requires a layout or
schema change, update this README and create a compatibility issue explaining
the observed failure, Codex version, config snippets, and fix.

## Setup

Codex setup creates a minimal usable Ars Contexta vault:

```bash
plugins/arscontexta/scripts/setup-vault.sh /path/to/new-vault --preset research --domain "research notes"
scripts/check-vault.sh /path/to/new-vault
```

Available presets are `research`, `personal`, and `experimental`. Use
`--dry-run` to preview files before writing:

```bash
plugins/arscontexta/scripts/setup-vault.sh /path/to/new-vault --preset personal --domain "life reflections" --dry-run
```

After setup, open the vault in Codex and run:

```text
Run an Ars Contexta health check on this vault.
```

The setup path reads bundled plugin presets and generator templates, then
generates `AGENTS.md`, `.arscontexta`, core folders, starter manual pages,
templates, starter notes, and operational config.

## Three-Space Architecture

Every generated system separates content into three spaces:

| Space | Purpose | Growth |
|-------|---------|--------|
| `self/` | Agent identity, methodology, goals, persistent operating memory | Slow |
| Domain notes | The knowledge graph itself | Steady |
| `ops/` | Queues, sessions, observations, tensions, health reports | Fluctuating |

The domain notes folder may be named `notes/`, `claims/`, `reflections/`,
`decisions/`, or something else. The separation is the invariant.

## Processing Pipeline

The vault implements the six Rs:

| Phase | Purpose |
|-------|---------|
| Record | Capture raw material with low friction |
| Reduce | Extract durable notes or claims |
| Reflect | Find connections and update topic maps |
| Reweave | Update older notes with new context |
| Verify | Check schema, links, descriptions, and quality |
| Rethink | Challenge assumptions and evolve methodology |

## Troubleshooting Codex Plugin Discovery

If **Agentic Note Taking** is not visible in the Codex plugin sidebar:

- Confirm `~/.codex/config.toml` has the `marketplaces.agenticnotetaking` block.
- Confirm `.agents/plugins/marketplace.json` exists in this repo.
- Fully quit and reopen Codex.

If **Agentic Note Taking** is visible but Ars Contexta skills are not:

- Confirm **Ars Contexta** is installed or enabled from the sidebar.
- Confirm `plugins/arscontexta/.codex-plugin/plugin.json` has `"skills": "./skills/"`.
- Confirm `plugins/arscontexta/skills/` contains skill directories.
- Start a fresh chat after installing.

If the skill fails with a model error, change `~/.codex/config.toml` to a
supported model such as:

```toml
model = "gpt-5.5"
```

## Search Requirements And Helper Scripts

Small, narrow, or low-processing vaults can run on `rg`, wiki-link traversal,
MOC/topic-map navigation, and bundled deterministic helper scripts. Large,
cross-domain, research, or heavy-processing vaults should use QMD-backed
semantic search, or an equivalent local semantic search tool, as part of the
working system. Without it, duplicate detection, description findability, and
cross-vocabulary connection discovery run in degraded mode.

QMD setup follows the upstream CLI shape:

```bash
npm install -g @tobilu/qmd
qmd collection add ~/path/to/markdown --name myknowledge
qmd embed
qmd status
```

The current deterministic helpers are CLI scripts, not a registered server:

```bash
plugins/arscontexta/scripts/mcp-vault-tools.sh links.check . --limit 25
plugins/arscontexta/scripts/mcp-vault-tools.sh frontmatter.validate . --file notes/example.md --limit 25
```

Skills must continue to fall back to bundled scripts, `rg`, and wiki-link
traversal when semantic search tooling is unavailable, but large-vault
recommendations and quality gates should report the missing search layer as a
degraded configuration rather than treating it as equivalent.

## Roadmap

| Work | Status |
|------|--------|
| Codex marketplace and plugin scaffold | Done |
| Codex-native vault setup | Done |
| Codex-native workflow skills | Done |
| Deterministic helper scripts | In progress |
| Optional indexed search tooling | Later |

## Philosophy

The name connects to a tradition: **Ars Combinatoria**, **Ars Memoria**,
**Ars Contexta**. The art of context.

Llull's wheels generated truth through combination. Bruno's memory wheels
created image combinations for recall. They were external thinking systems:
tools to think with, not just places to store things. Ars Contexta brings that
lineage into agent-operated knowledge graphs.

Built on the Tools for Thought for Agents research tradition.

## License

MIT
