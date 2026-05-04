# HippocampusMD

**Agent memory OS for local markdown knowledge systems.**

HippocampusMD helps Codex maintain durable working memory: plain markdown
notes, wiki links, processing queues, operational state, and Obsidian-friendly
navigation.

**v1.0.0** | Codex-only local plugin | MIT

Codex is the only supported HippocampusMD distribution in this repo.
Claude Code support, hooks, slash commands, and legacy generated skill templates have been removed.

## What It Does

Most agent sessions start blank. HippocampusMD gives Codex a local memory
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
plugins/hippocampusmd/.codex-plugin/plugin.json
plugins/hippocampusmd/skills/
plugins/hippocampusmd/scripts/
```

Add this marketplace to `~/.codex/config.toml`:

```toml
[marketplaces.hippocampusmd]
source_type = "local"
source = "/Users/hlee/Desktop/playgrounds/hippocampusmd"

[plugins."hippocampusmd@hippocampusmd"]
enabled = true
```

Then open Codex, go to **Codex Plugins** in the left sidebar, open the
**HippocampusMD** marketplace, and install or enable **HippocampusMD**.
Start a fresh chat after installing.

## Supported Skills

The installable Codex plugin includes skills for setup, help, health,
validation, session workflows, queue processing, graph diagnostics, note
extraction, reflection, evolution, recommendations, tutorial onboarding, and
research capture.

Typical prompts:

```text
What can HippocampusMD do here?
Run a HippocampusMD health check on this vault.
Set up HippocampusMD here for my research notes.
Use hippocampusmd-pipeline to plan this source.
Use hippocampusmd-session to capture a handoff.
```

Codex session workflows are explicit. They do not auto-commit or run in the
background.

## Repository Layout

```text
hippocampusmd/
|-- .agents/plugins/marketplace.json       # Codex local marketplace
|-- plugins/hippocampusmd/                   # Installable Codex plugin package
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

plugins/hippocampusmd/ is the source of truth for the runtime plugin. Edit
plugin metadata, Codex-native skills, bundled scripts, agents, generators,
presets, and bundled knowledge there. The plugin-side
`plugins/hippocampusmd/agents/`, `plugins/hippocampusmd/generators/`,
`plugins/hippocampusmd/presets/`, `plugins/hippocampusmd/methodology/`, and
`plugins/hippocampusmd/reference/` directories are not copied into user vaults;
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

`origin` should point at the standalone HippocampusMD repository through the
personal SSH alias:

```text
origin git@github-hojaeklee:hojaeklee/hippocampusmd.git
```

The old fork relationship should be detached in GitHub before or during the
repository rename. This repo should not keep an `upstream` remote for the
original project after the identity migration.

### Updating The Codex Plugin

For Codex, treat the installable package as the source of truth. Edit:

```text
plugins/hippocampusmd/.codex-plugin/plugin.json
plugins/hippocampusmd/skills/<skill-name>/SKILL.md
plugins/hippocampusmd/scripts/
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

1. Open the **Codex Plugins** sidebar and confirm **HippocampusMD** still appears.
2. Confirm **HippocampusMD** is still installed or enabled.
3. Start a fresh chat in this repo and verify HippocampusMD skills are available.
4. Start a fresh chat in a real vault and run a HippocampusMD health check.

Keep update fixes small and documented. If a Codex update requires a layout or
schema change, update this README and create a compatibility issue explaining
the observed failure, Codex version, config snippets, and fix.

## Setup

Codex setup creates a minimal usable HippocampusMD vault:

```bash
plugins/hippocampusmd/scripts/setup-vault.sh /path/to/new-vault --preset research --domain "research notes"
scripts/check-vault.sh /path/to/new-vault
```

Available presets are `research`, `personal`, and `experimental`. Use
`--dry-run` to preview files before writing:

```bash
plugins/hippocampusmd/scripts/setup-vault.sh /path/to/new-vault --preset personal --domain "life reflections" --dry-run
```

After setup, open the vault in Codex and run:

```text
Run a HippocampusMD health check on this vault.
```

The setup path reads bundled plugin presets and generator templates, then
generates `AGENTS.md`, `.hippocampusmd`, core folders, starter manual pages,
templates, starter notes, and operational config.

## Vault Configuration

`ops/config.yaml` is the vault-local configuration contract. Setup generates
safe defaults, and users may edit it when the live vault shape changes.

The `scan:` section controls which markdown files deterministic helpers treat
as active vault content. Include rules define the candidate file set, and
exclude rules win when both match. This keeps imported sources, archives,
attachments, generated reports, cache files, and old operational history from
polluting index, status, and later large-vault command output.

```yaml
scan:
  include:
    - notes/**
    - self/**
    - manual/**
    - inbox/**
    - ops/derivation.md
    - ops/derivation-manifest.md
  exclude:
    - archive/**
    - imported/**
    - attachments/**
    - ops/cache/**
    - ops/health/**
    - ops/sessions/**
    - ops/queue/archive/**
```

`hippocampusmd-index` reports ignored-file counts after a build and in status
output. If expected notes are missing from the index, inspect `scan.include`
and `scan.exclude` first.

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

If **HippocampusMD** is not visible in the Codex plugin sidebar:

- Confirm `~/.codex/config.toml` has the `marketplaces.hippocampusmd` block.
- Confirm `.agents/plugins/marketplace.json` exists in this repo.
- Fully quit and reopen Codex.

If **HippocampusMD** is visible but HippocampusMD skills are not:

- Confirm **HippocampusMD** is installed or enabled from the sidebar.
- Confirm `plugins/hippocampusmd/.codex-plugin/plugin.json` has `"skills": "./skills/"`.
- Confirm `plugins/hippocampusmd/skills/` contains skill directories.
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
plugins/hippocampusmd/scripts/mcp-vault-tools.sh links.check . --limit 25
plugins/hippocampusmd/scripts/mcp-vault-tools.sh frontmatter.validate . --file notes/example.md --limit 25
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

## Support

HippocampusMD is a personal open-source project. Support is optional and helps
fund continued work on the plugin, docs, and local-first knowledge-system
experiments.

- GitHub Sponsors: https://github.com/sponsors/hojaeklee
- Buy Me a Coffee: TODO after the Buy Me a Coffee username is created.

GitHub Sponsors is the native GitHub option and does not charge fees for
personal-account sponsorships. Buy Me a Coffee is better for casual one-time
tips, with a 5% platform fee plus Stripe payment processing.

## Philosophy

The name points at the hippocampus as a memory system rather than a storage
box. HippocampusMD treats markdown vaults as living context for agents:
something Codex can orient through, maintain, and evolve while the user keeps
ownership of the files.

Built on the Tools for Thought for Agents research tradition.

## License

MIT
