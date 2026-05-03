---
name: arscontexta-recommend
description: Use when the user asks Codex for Ars Contexta architecture advice, knowledge-system recommendations, preset comparisons, or guidance for a new vault use case.
---

# Ars Contexta Recommend

Give research-backed architecture recommendations from local Ars Contexta sources. This skill is advisory and read-only: recommend a shape, explain trade-offs, and name follow-up options, but do not create or edit files.

## When Invoked

1. Treat the current working directory as the context unless the user gives another path.
2. Parse the user's use case for signals:
   - domain, goals, pain points, expected scale, platform, existing system, operator, processing depth, and maintenance tolerance.
3. If the request is too sparse, ask at most 1-2 clarifying questions, then recommend with stated assumptions.
4. Search with `rg` and read local files before using optional semantic tooling.

## Source Order

Use local `reference/` and `methodology/` files first. Start with the most relevant of:

- `reference/tradition-presets.md`
- `reference/methodology.md`
- `reference/components.md`
- `reference/dimension-claim-map.md`
- `reference/interaction-constraints.md`
- `reference/claim-map.md`
- related methodology claims under `methodology/`

Optional QMD, semantic search, or indexed knowledge tools may be used only when already available. Never require them and never present unavailable external tools as Codex requirements.

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
- Keep `arscontexta-recommend` distinct from `arscontexta-ask`: ask answers methodology questions, recommend gives architecture advice for a use case.
- Use Codex skill language; do not assume Claude slash-command invocation.
