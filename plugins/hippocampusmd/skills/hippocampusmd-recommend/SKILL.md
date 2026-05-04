---
name: hippocampusmd-recommend
description: Use when the user asks Codex for HippocampusMD architecture advice, knowledge-system recommendations, preset comparisons, or guidance for a new vault use case.
---

# HippocampusMD Recommend

Give research-backed architecture recommendations from local HippocampusMD sources. This skill is advisory and read-only: recommend a shape, explain trade-offs, and name follow-up options, but do not create or edit files.

## When Invoked

1. Treat the current working directory as the context unless the user gives another path.
2. Parse the user's use case for signals:
   - domain, goals, pain points, expected scale, platform, existing system, operator, processing depth, and maintenance tolerance.
3. If the request is too sparse, ask at most 1-2 clarifying questions, then recommend with stated assumptions.
4. Search with `rg` and read local files before using optional semantic tooling.

## Source Order

Use local `plugins/hippocampusmd/reference/` and `plugins/hippocampusmd/methodology/` files first. Start with the most relevant of:

- `plugins/hippocampusmd/reference/tradition-presets.md`
- `plugins/hippocampusmd/reference/methodology.md`
- `plugins/hippocampusmd/reference/components.md`
- `plugins/hippocampusmd/reference/dimension-claim-map.md`
- `plugins/hippocampusmd/reference/interaction-constraints.md`
- `plugins/hippocampusmd/reference/claim-map.md`
- related methodology claims under `plugins/hippocampusmd/methodology/`

Use QMD, semantic search, or indexed knowledge tools only when they are already available for your own search process. In architecture recommendations, require QMD or equivalent semantic search for large, cross-domain, research, or heavy-processing vaults unless the user explicitly accepts degraded discovery. Small or narrow low-volume vaults may start with `rg` plus MOC/topic-map traversal and add semantic search when scale or friction demands it.
Never require them, and never present unavailable external tools as Codex requirements.

## Recommendation Shape

- Lead with the recommended architecture in plain language.
- Name the closest preset or blend of presets, with match quality.
- Recommend positions for the core configuration dimensions: granularity, organization, linking, processing, navigation, maintenance, schema, and automation.
- Explain the rationale with citations to local reference or methodology paths when useful.
- Call out hard constraints, soft warnings, caveats, and assumptions.
- End with one concrete next step, such as running setup later or refining the recommendation with more constraints.

## Boundaries

- Do not generate a vault, scaffold files, update tasks, or mutate queues.
- Do not apply architecture changes to an existing vault; that belongs to setup, architect, or refactor-style follow-up work.
- Keep `hippocampusmd-recommend` distinct from `hippocampusmd-ask`: ask answers methodology questions, recommend gives architecture advice for a use case.
- Use Codex skill language; do not assume Claude slash-command invocation.
