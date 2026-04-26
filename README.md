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
| Codex | In progress | Local plugin scaffold exists. Codex-native help, health, and minimal setup skills are available. |
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
plugins/arscontexta/skills/arscontexta-help/SKILL.md
plugins/arscontexta/skills/arscontexta-health/SKILL.md
plugins/arscontexta/skills/arscontexta-setup/SKILL.md
plugins/arscontexta/skills/arscontexta-session/SKILL.md
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

### Supported Codex Skills

The current Codex-native skills are:

```text
arscontexta-help
arscontexta-health
arscontexta-setup
arscontexta-session
```

Use help when you want orientation in the plugin repo, a vault, or a generic directory:

```text
What can Ars Contexta do here?
```

Use health from an Ars Contexta or Obsidian vault:

```text
Run an Ars Contexta health check on this vault.
```

or explicitly:

```text
Use arscontexta-health to diagnose this Obsidian vault.
```

Use setup in an empty directory or existing markdown vault when you want Codex to
create minimal Ars Contexta scaffolding:

```text
Set up Ars Contexta here for my research notes.
```

Minimal Codex setup creates `AGENTS.md`, `.arscontexta`, core folders, starter
manual pages, templates, and operational config. Full Claude setup parity,
runtime processing skills, and background hooks are still being ported.

Use session workflows when you want Codex to do the work Claude hooks used to do
automatically:

```text
Use arscontexta-session to orient in this vault.
Use arscontexta-session to validate changed notes.
Use arscontexta-session to capture a handoff for the next session.
```

Codex session workflows are explicit. They do not auto-commit or run in the
background.

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
|   +-- skills/
|       |-- arscontexta-help/SKILL.md
|       |-- arscontexta-health/SKILL.md
|       +-- arscontexta-setup/SKILL.md
|-- .codex-plugin/plugin.json              # Root Codex manifest for development/reference
|-- .claude-plugin/
|   |-- plugin.json                        # Claude plugin manifest
|   +-- marketplace.json                   # Claude marketplace listing
|-- skills/                                # Claude plugin skills plus Codex-port candidates
|   |-- setup/
|   |-- help/
|   |-- health/
|   |-- arscontexta-help/
|   |-- arscontexta-health/
|   +-- arscontexta-setup/
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
skills/arscontexta-help/SKILL.md
skills/arscontexta-setup/SKILL.md
skills/arscontexta-session/SKILL.md
plugins/arscontexta/skills/arscontexta-health/SKILL.md
plugins/arscontexta/skills/arscontexta-help/SKILL.md
plugins/arscontexta/skills/arscontexta-setup/SKILL.md
plugins/arscontexta/skills/arscontexta-session/SKILL.md
```

After editing:

```bash
scripts/check-codex-plugin.sh
git status --short
```

Restart Codex before testing plugin discovery. Existing chats do not reliably
hot-reload plugin skills.

### When Codex Updates

Treat Codex app/runtime updates as compatibility events. Ars Contexta previously
broke across Claude Code versions because plugin schemas, hooks, model names, and
runtime assumptions changed underneath it. Codex can do the same.

After each Codex update, run the compatibility smoke tests:

```bash
scripts/check-codex-plugin.sh
scripts/check-vault.sh "/Users/hlee/Library/CloudStorage/GoogleDrive-hojae.k.lee@gmail.com/My Drive/knowledge-base"
```

The scripts print `PASS`, `WARN`, and `FAIL` lines. Warnings are diagnostic; a
nonzero exit means at least one failure needs attention before trusting the
plugin in a new session.

Then confirm the Codex UI state that scripts cannot inspect directly:

1. Open the **Codex Plugins** sidebar and confirm **Agentic Note Taking** still
   appears.
2. Confirm **Ars Contexta** is still installed or enabled.
3. Start a fresh chat in this repo and verify `$` shows `arscontexta-help`,
   `arscontexta-health`, and `arscontexta-setup`.
4. Start a fresh chat in a real vault and run:

   ```text
   Use arscontexta-health to diagnose this vault.
   ```

5. If discovery breaks, first check marketplace shape, plugin manifest fields,
   skill path conventions, `~/.codex/config.toml`, and whether Codex now requires
   a cache refresh or reinstall from the sidebar.

Keep update fixes small and documented. If a Codex update requires a layout or
schema change, update this README and create a compatibility issue explaining the
observed failure, Codex version, config snippets, and the fix.

### Porting More Codex Skills

Port Claude slash-command skills into Codex-native skills incrementally.
Recommended order:

1. `arscontexta-ask`
2. `arscontexta-recommend`
3. `arscontexta-reduce`
4. `arscontexta-reflect`
5. `arscontexta-reweave`
6. `arscontexta-verify`
7. `arscontexta-remember`
8. maintenance and evolution skills beyond health

Codex skills should be shorter than the Claude command bodies. Put only the core
workflow in `SKILL.md`, move long methodology into `reference/`, and use scripts
for deterministic checks.

### Minimal Codex Setup

Codex setup is available as a conservative first slice. It creates the smallest
usable Ars Contexta vault without Claude hooks. Instead of installing background
hooks, it points Codex at explicit session workflows:

```bash
scripts/setup-vault.sh /path/to/new-vault --preset research --domain "research notes"
scripts/check-vault.sh /path/to/new-vault
```

Available presets are `research`, `personal`, and `experimental`. Use
`--dry-run` to preview files before writing:

```bash
scripts/setup-vault.sh /path/to/new-vault --preset personal --domain "life reflections" --dry-run
```

After setup, open the vault in Codex and run:

```text
Run an Ars Contexta health check on this vault.
```

The Codex setup path generates `AGENTS.md` only. It preserves any existing
`CLAUDE.md` and does not install `.claude/` hooks or settings. Use
`arscontexta-session orient`, `arscontexta-session validate`, and
`arscontexta-session capture` when you want Codex to perform the session-rhythm
work that Claude hooks automate.

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

If **Agentic Note Taking** is visible but `arscontexta-help`,
`arscontexta-health`, or `arscontexta-setup` is not:

- Confirm **Ars Contexta** is installed or enabled from the sidebar.
- Confirm `plugins/arscontexta/.codex-plugin/plugin.json` has `"skills": "./skills/"`.
- Confirm `plugins/arscontexta/skills/arscontexta-help/SKILL.md` exists.
- Confirm `plugins/arscontexta/skills/arscontexta-health/SKILL.md` exists.
- Confirm `plugins/arscontexta/skills/arscontexta-setup/SKILL.md` exists.
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
| Port `arscontexta-help` to Codex | Done |
| Port minimal Codex setup flow | Done |
| Port full setup parity | Planned |
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
