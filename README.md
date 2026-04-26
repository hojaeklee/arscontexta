# Ars Contexta

**Agent-native knowledge-system architecture for local markdown vaults.**

Ars Contexta helps an AI agent maintain a durable thinking system: plain
markdown notes, wiki links, processing queues, operational memory, and
Obsidian-friendly navigation. It began as a Claude Code plugin and is now being
ported to Codex as a first-class local plugin.

**v0.8.1** | Codex plugin in progress | Claude Code plugin available | MIT

## Current Status

| Platform | Status | Notes |
|----------|--------|-------|
| Codex | In progress | Local plugin scaffold exists. First Codex-native skill is `arscontexta-health`. |
| Claude Code | Available | Original plugin remains intact under `.claude-plugin/` and `skills/`. |
| MCP | Not implemented | Good future target for deterministic vault operations, not the main methodology. |

The repo intentionally keeps Claude and Codex support side by side. Do not remove
the Claude plugin while porting Codex skills.

## What It Does

Most agent sessions start blank. Ars Contexta gives the agent a local memory
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
plugins/arscontexta/skills/arscontexta-health/SKILL.md
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

### Supported Codex Skill

The first Codex-native skill is:

```text
arscontexta-health
```

Use it from an Ars Contexta or Obsidian vault:

```text
Run an Ars Contexta health check on this vault.
```

or explicitly:

```text
Use arscontexta-health to diagnose this Obsidian vault.
```

### Codex Model Note

If you use Codex with a ChatGPT account, avoid this config:

```toml
model = "gpt-5-codex"
```

Use a supported model instead, for example:

```toml
model = "gpt-5.5"
```

Otherwise Codex may fail with:

```text
The 'gpt-5-codex' model is not supported when using Codex with a ChatGPT account.
```

## Use With Claude Code

Claude Code remains the mature implementation.

Add the marketplace:

```text
/plugin marketplace add agenticnotetaking/arscontexta
```

Install the plugin:

```text
/plugin install arscontexta@agenticnotetaking
```

Restart Claude Code, then run:

```text
/arscontexta:setup
```

After setup, restart Claude Code again so generated hooks and skills activate.
Then run:

```text
/arscontexta:help
```

## Repository Layout

```text
arscontexta/
|-- .agents/plugins/marketplace.json       # Codex local marketplace
|-- plugins/arscontexta/                   # Installable Codex plugin package
|   |-- .codex-plugin/plugin.json
|   +-- skills/arscontexta-health/SKILL.md
|-- .codex-plugin/plugin.json              # Root Codex manifest for development/reference
|-- .claude-plugin/
|   |-- plugin.json                        # Claude plugin manifest
|   +-- marketplace.json                   # Claude marketplace listing
|-- skills/                                # Claude plugin skills plus Codex-port candidates
|   |-- setup/
|   |-- help/
|   |-- health/
|   +-- arscontexta-health/
|-- skill-sources/                         # Generated vault skill templates
|-- hooks/                                 # Claude hook configuration and scripts
|-- generators/                            # CLAUDE.md and feature generation sources
|-- methodology/                           # Research claims and methodology notes
|-- reference/                             # Core references and templates
|-- platforms/                             # Platform-specific adapters
|-- presets/                               # Starter configurations
|-- scripts/                               # Utility scripts
+-- README.md
```

The installable Codex package currently duplicates a small manifest and skill
under `plugins/arscontexta/` because Codex local marketplaces expect the
conventional `plugins/<name>` layout.

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

### Updating From Upstream

If the original repository ever changes:

```bash
git fetch upstream
git log --oneline main..upstream/main
```

Then merge or cherry-pick deliberately. Do not assume upstream is maintained.

### Updating The Codex Plugin

For now, keep the Codex install package and root development files in sync when
editing plugin metadata or the first skill:

```text
.codex-plugin/plugin.json
plugins/arscontexta/.codex-plugin/plugin.json
skills/arscontexta-health/SKILL.md
plugins/arscontexta/skills/arscontexta-health/SKILL.md
```

After editing:

```bash
jq . .agents/plugins/marketplace.json
jq . plugins/arscontexta/.codex-plugin/plugin.json
git status --short
```

Restart Codex before testing plugin discovery. Existing chats do not reliably
hot-reload plugin skills.

### Porting More Codex Skills

Port Claude slash-command skills into Codex-native skills incrementally.
Recommended order:

1. `arscontexta-help`
2. `arscontexta-setup`
3. `arscontexta-ask`
4. `arscontexta-reduce`
5. `arscontexta-reflect`
6. `arscontexta-reweave`
7. `arscontexta-verify`
8. `arscontexta-remember`

Codex skills should be shorter than the Claude command bodies. Put only the core
workflow in `SKILL.md`, move long methodology into `reference/`, and use scripts
for deterministic checks.

## Claude Commands

Plugin-level Claude commands:

| Command | What It Does |
|---------|-------------|
| `/arscontexta:setup` | Conversational onboarding and vault generation |
| `/arscontexta:help` | Contextual command guidance |
| `/arscontexta:tutorial` | Interactive walkthrough |
| `/arscontexta:ask` | Query methodology and vault knowledge |
| `/arscontexta:health` | Run vault diagnostics |
| `/arscontexta:recommend` | Get architecture advice |
| `/arscontexta:architect` | Research-backed evolution guidance |
| `/arscontexta:add-domain` | Add a knowledge domain |
| `/arscontexta:reseed` | Re-derive when drift accumulates |
| `/arscontexta:upgrade` | Apply plugin knowledge-base updates |

Generated vault commands include `reduce`, `reflect`, `reweave`, `verify`,
`validate`, `seed`, `ralph`, `pipeline`, `tasks`, `stats`, `graph`, `next`,
`learn`, `remember`, `rethink`, and `refactor`.

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

If **Agentic Note Taking** is visible but `arscontexta-health` is not:

- Confirm **Ars Contexta** is installed or enabled from the sidebar.
- Confirm `plugins/arscontexta/.codex-plugin/plugin.json` has `"skills": "./skills/"`.
- Confirm `plugins/arscontexta/skills/arscontexta-health/SKILL.md` exists.
- Start a fresh chat after installing.

If the skill fails with a model error:

- Change `~/.codex/config.toml` from `gpt-5-codex` to a supported model such as
  `gpt-5.5`.

## Semantic Search

Semantic search is optional. The system should work with `rg` and wiki-link
traversal alone.

`qmd` may become useful later as an MCP-backed search bridge:

```bash
npm install -g @tobilu/qmd
cd your-vault/
qmd init
qmd collection add . --name notes --mask "notes/**/*.md"
qmd embed
```

MCP integration should be reserved for deterministic operations such as graph
analysis, YAML/frontmatter validation, link checks, queue operations, schema-aware
note creation, and vault indexing.

## Roadmap

| Work | Status |
|------|--------|
| Preserve Claude Code plugin | Done |
| Add Codex marketplace and plugin scaffold | Done |
| Port `arscontexta-health` to Codex | Done |
| Port `arscontexta-help` to Codex | Next |
| Port Codex setup flow | Planned |
| Add deterministic MCP tools | Later |

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
