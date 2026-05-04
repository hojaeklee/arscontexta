---
name: hippocampusmd-help
description: Use when the user asks what HippocampusMD can do, how to use this vault, how to use the plugin repo, what to do next, or asks for HippocampusMD help in Codex.
---

# HippocampusMD Help

Give concise, context-aware guidance for HippocampusMD in Codex. Explain what is available now and the single most useful next action.

## When Invoked

1. Treat the current working directory as the target context unless the user gives another path.
2. Detect the context with light inspection only:
   - Plugin repo: `.agents/plugins/marketplace.json`, `plugins/hippocampusmd/.codex-plugin/plugin.json`, or this repo README exists.
   - HippocampusMD vault: `.hippocampusmd` exists.
   - Obsidian-style vault: markdown files and vault-like directories exist, but `.hippocampusmd` is absent.
   - Generic directory: none of the above.
3. Do not run health scans, schema validation, dangling-link checks, or queue analysis. If the user wants diagnostics, recommend `hippocampusmd-health`.

## Context Responses

### Plugin Repo

Explain that this is the HippocampusMD Codex plugin source. `plugins/hippocampusmd/` is the source of truth for installable skills, bundled helper scripts, generators, presets, and plugin-side knowledge.

Available now:

- `hippocampusmd-help`: contextual orientation for Codex.
- `hippocampusmd-health`: quick vault health checks.
- `hippocampusmd-setup`: minimal Codex-native vault scaffolding.
- `plugins/hippocampusmd/scripts/vault-health.sh`: bounded link-health helper.
- `plugins/hippocampusmd/scripts/setup-vault.sh`: deterministic minimal setup helper.
- `plugins/hippocampusmd/generators/`: bundled context and feature generator sources.
- `plugins/hippocampusmd/presets/`: bundled preset configs and starter notes.
- `hippocampusmd-validate`: detailed read-only note/schema validation.
- `hippocampusmd-tasks`: task stack and queue-state visibility for Codex.
- `hippocampusmd-next`: one read-only recommendation for what to do next.
- `hippocampusmd-index`: natural-language access to build, inspect, or export the persisted VaultIndex.
- `hippocampusmd-stats`: concise vault metrics and shareable graph snapshots.
- `hippocampusmd-graph`: bounded graph diagnostics for orphans, hubs, sparse areas, and synthesis opportunities.
- `hippocampusmd-ask`: source-grounded methodology Q&A for Codex.
- `hippocampusmd-recommend`: read-only architecture advice for new vault use cases.
- `hippocampusmd-reduce`: source extraction into durable notes with explicit write approval.
- `hippocampusmd-reflect`: connection discovery and focused note/topic-map weaving.
- `hippocampusmd-reweave`: backward-link and older-note refresh workflow.
- `hippocampusmd-verify`: bounded quality gate for note readiness.
- `hippocampusmd-remember`: confirmed methodology, observation, and tension capture.
- `hippocampusmd-rethink`: evidence-backed review of observations, tensions, drift, and proposals.
- `hippocampusmd-architect`: advisory architecture review for existing vault evolution.
- `hippocampusmd-refactor`: report-only restructuring plans for chosen config or derivation shifts.
- `hippocampusmd-reseed`: content-preserving re-derivation analysis for structural drift.
- `hippocampusmd-upgrade`: advisory generated-skill upgrade analysis against current methodology.
- `hippocampusmd-add-domain`: previewed composition of a new domain into an existing vault.
- `hippocampusmd-seed`: deterministic queue seeding for inbox or local source files.
- `hippocampusmd-ralph`: dry-run and run explicit queue phases with Codex subagent boundaries.
- `hippocampusmd-pipeline`: visible end-to-end source processing orchestration.
- `hippocampusmd-archive-batch`: deterministic cleanup for completed processing batches.
- `hippocampusmd-tutorial`: safe conversational onboarding with preview-first tutorial notes.
- `hippocampusmd-learn`: opt-in research capture with provenance and pipeline handoff.
- `scripts/check-codex-plugin.sh` and `scripts/check-vault.sh`: Codex compatibility smoke tests.

Recommend one next action:

- Run `scripts/check-codex-plugin.sh` after plugin edits or Codex updates.
- Run `scripts/check-vault.sh <vault-path>` before testing against a real vault.
- Use `plugins/hippocampusmd/skills/` when editing installable skill behavior.
- Use `plugins/hippocampusmd/generators/` and `plugins/hippocampusmd/presets/` when editing setup-derived vault outputs.

### HippocampusMD Vault

Explain that the directory is a HippocampusMD vault: markdown notes, wiki links, `ops/` state, and optional `self/` memory.
Mention that `ops/config.yaml` is the user-editable vault configuration surface for folders, vocabulary, workflows, and scan rules; it is not hidden internal state.

Available now in Codex:

- Ask for HippocampusMD help to orient yourself.
- Run `hippocampusmd-health` to check vault structure, schema signals, links, orphans, queues, and health state.
- Run `hippocampusmd-setup` to create or complete minimal Codex vault scaffolding.
- Run `hippocampusmd-validate` to check note frontmatter, schema fields, descriptions, enums, and wiki links.
- Run `hippocampusmd-tasks` to inspect or explicitly update `ops/tasks.md`.
- Run `hippocampusmd-next` to get one bounded, rationale-backed next action.
- Run `hippocampusmd-index` to build, inspect, or export the persisted VaultIndex without remembering helper paths.
- Run `hippocampusmd-stats` to summarize graph size, health, growth, and pipeline state.
- Run `hippocampusmd-graph` to inspect graph structure and connection opportunities.
- Run `hippocampusmd-ask` for source-grounded answers about HippocampusMD methodology.
- Run `hippocampusmd-recommend` for research-backed architecture advice before setup.
- Run `hippocampusmd-reduce` to extract notes from source material or inbox items.
- Run `hippocampusmd-reflect` to find and apply meaningful note connections.
- Run `hippocampusmd-reweave` to revisit older or sparse notes with current context.
- Run `hippocampusmd-verify` to quality-check one note or a small changed set.
- Run `hippocampusmd-remember` to capture confirmed learnings or session patterns.
- Run `hippocampusmd-rethink` to review accumulated observations, tensions, or methodology drift.
- Run `hippocampusmd-architect` for evidence-backed architecture evolution advice.
- Run `hippocampusmd-refactor` to plan approved config, schema, navigation, or structure changes.
- Run `hippocampusmd-reseed` when drift suggests re-derivation rather than incremental fixes.
- Run `hippocampusmd-upgrade` to compare generated vault skills against current methodology.
- Run `hippocampusmd-add-domain` to derive and preview a new domain addition.
- Run `hippocampusmd-seed` to add an inbox or local source file to the processing queue.
- Run `hippocampusmd-ralph` to dry-run or process pending queue phases explicitly.
- Run `hippocampusmd-pipeline` to plan and orchestrate one source through the processing workflow.
- Run `hippocampusmd-archive-batch` to archive a completed processing batch.
- Run `hippocampusmd-tutorial` for a preview-first guided walkthrough before writing sample notes.
- Run `hippocampusmd-learn` to capture research with explicit provenance before queueing it.
- Use the manual if `manual/` exists.

Recommend one next action:

- If the user asks "what should I do next", suggest running `hippocampusmd-health`.
- If `manual/getting-started.md` exists, mention it as the best human-readable orientation.
- If `manual/` exists but no getting-started page is obvious, mention browsing `manual/`.

### Obsidian-Style Vault Without HippocampusMD

Explain that this looks like a markdown vault, but HippocampusMD configuration was not detected.

Recommend one next action:

- If the user wants diagnostics anyway, run `hippocampusmd-health` as a generic Obsidian-vault check.
- If the user wants HippocampusMD structure, recommend `hippocampusmd-setup` for minimal Codex scaffolding.

### Generic Directory

Explain that HippocampusMD works best when Codex is opened in either:

- the HippocampusMD plugin repo, or
- a HippocampusMD or Obsidian markdown vault.

Recommend one next action:

- Open Codex in the vault directory.
- Or install/enable the local plugin from the HippocampusMD marketplace if that has not been done.

## Response Rules

- Give one recommended next action, not a long menu.
- Use Codex language: "ask Codex", "run the health skill", "open this vault".
- Use Codex file workflows, plugin skill names, and explicit user intent.
- Keep the response focused and avoid full command catalogs.
- Prefer concrete local paths when they are obvious.
