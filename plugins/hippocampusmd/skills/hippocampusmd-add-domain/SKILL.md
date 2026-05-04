---
name: hippocampusmd-add-domain
description: Use when the user asks Codex to add a new HippocampusMD knowledge domain to an existing vault, derive domain vocabulary or schema, or preview multi-domain composition.
---

# HippocampusMD Add Domain

Compose a new knowledge domain into an existing vault. This skill derives a domain-specific folder, vocabulary, schema, templates, and MOC connections while preserving the current vault architecture.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation.md` for original design intent and existing derivation notes.
   - `ops/config.yaml` for configured folders, features, dimensions, and vocabulary.
   - `ops/derivation-manifest.md` for generated vocabulary, paths, and platform hints.
3. Inventory existing domains, notes folders, templates, MOCs, vocabulary, schemas, and shared `self/` and `ops/` infrastructure before proposing anything.
4. Use local file reads and `rg` for bounded inspection. Do not depend on external services or hidden generation state.

## Conversation Signals

Use a minimal Codex conversation. Ask one focused opening question about the new domain, then at most one or two follow-ups if required.

Extract these signals:

- purpose and operating context
- vocabulary the user naturally uses
- cross-domain relationship to existing domains
- expected volume and temporal dynamics
- processing intensity and maintenance needs
- schema needs and likely frontmatter fields
- linking patterns, shared concepts, and likely MOC placement

Do not ask the user to choose abstract architecture dimensions directly. Translate their answers into a proposal.

## Domain Configuration

Distinguish system-level dimensions from domain-adjustable dimensions.

- System-level dimensions usually stay shared: organization model, automation posture, navigation depth, shared `self/`, and shared `ops/`.
- Domain-adjustable dimensions can vary by domain: granularity, processing intensity, maintenance cadence, schema detail, vocabulary transforms, and linking density.

Consult local `plugins/hippocampusmd/reference/` files first, especially:

- `derivation-validation.md`
- `three-spaces.md`
- `interaction-constraints.md`
- `vocabulary-transforms.md`
- `tradition-presets.md`
- `use-case-presets.md`
- `dimension-claim-map.md`
- `failure-modes.md`

Check collisions across filenames, folders, template names, schema fields, vocabulary terms, and MOC titles before proposing writes.

## Proposal First

Default to a domain-addition proposal before generating files. The proposal should preview:

- folders and notes folders affected
- templates and schema fields
- vocabulary and naming transforms
- domain MOC and hub MOC update
- composition rules for links, shared concepts, and cross-domain search
- content impact and existing architecture preservation
- derivation update, context updates, and optional processing-skill updates
- validation steps and rollback expectations

Require confirmation before generation. Do not create folders, templates, domain MOCs, hub MOC updates, context files, self methodology changes, derivation records, semantic search config, or processing skills until the user approves the specific proposal.

## Approved Generation

When the user confirms, make only the approved changes:

- create approved folders and templates
- create the approved domain MOC
- apply the approved hub MOC update
- update derivation records only when included in the approved derivation update
- update context, self methodology, semantic search config, or processing skills only when explicitly approved

Always preserve existing architecture and avoid replacing existing domain files. If a collision is discovered during generation, stop and ask before choosing a new name or overwriting anything.

## Validation

After approved writes, run or recommend validation that covers:

- kernel checks and core HippocampusMD invariants
- YAML/frontmatter validity
- wiki links and cross-domain link resolution
- hub reachability from the central MOC to the new domain MOC
- filename uniqueness
- schema conflicts and field collisions
- vocabulary isolation between domains
- template usability and MOC discoverability

Use existing validation helpers when available, such as `scripts/check-vault.sh`, `plugins/hippocampusmd/scripts/validate-vault.sh`, and `hippocampusmd-validate`.

## Boundaries

- This skill composes a new domain into the current vault. It does not reseed, replace, or re-derive the entire architecture.
- Keep writes explicit, previewed, and confirmed.
- Do not mutate `ops/queue/*`, run pipeline tasks, or silently change existing content.
- Use Codex file workflows, local inspection, and explicit user approval.
