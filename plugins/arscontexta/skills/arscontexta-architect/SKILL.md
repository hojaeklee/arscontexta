---
name: arscontexta-architect
description: Use when the user asks Codex to review or evolve an existing Ars Contexta vault architecture, diagnose system drift, or recommend evidence-backed vault changes.
---

# Ars Contexta Architect

Review an existing vault architecture and recommend bounded evolution. Architect is advisory by default: it explains what should change and why, but does not apply architecture changes itself.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary, domain language, platform hints, and follow-up skill names.
   - `ops/config.yaml` for current live configuration and enabled workflow signals.
   - `ops/derivation.md` for original design intent, dimension choices, conversation signals, risks, and rationale.
3. Choose the smallest useful mode:
   - full-system review: analyze the whole vault architecture.
   - focused-area review: prioritize a named area such as schema, processing, navigation, graph, or maintenance.
   - dry-run or report-only: produce recommendations without offering implementation.
4. Warn when derivation or config files are missing; continue with current-state evidence when possible.

## Evidence Sources

- Inspect recent health reports, or use bounded health, stats, graph, validate, and next helpers when available.
- Read observations, tensions, methodology notes, recent sessions, goals, templates, queue state, and graph signals when present.
- Compare current behavior against design intent and vocabulary rather than assuming universal Ars Contexta terms.
- Distinguish between urgent health failures, repeated friction, design drift, and speculative optimization.

## Research Grounding

- Consult local `reference/` sources first:
  - `dimension-claim-map.md`
  - `interaction-constraints.md`
  - `methodology.md`
  - `failure-modes.md`
  - `tradition-presets.md`
  - `three-spaces.md`
  - `evolution-lifecycle.md`
- Use QMD or semantic search only when already available; never require it.
- cite local vault evidence and cite local reference paths for each recommendation.

## Output

- Produce 3-5 ranked recommendations, or fewer when evidence is thin.
- For each recommendation include: evidence, research grounding, proposed change, interaction effects, risk, reversibility, estimated effort, expected benefit, and next step.
- Lead with the most useful architecture advice, then show the evidence chain.
- Name whether the next step is `arscontexta-refactor`, `arscontexta-reseed`, or a separate explicit follow-up.
- Keep `arscontexta-architect` distinct from `arscontexta-recommend`: recommend advises new vault architecture; architect reviews and evolves an existing vault.

## Boundaries

- Do not auto-implement architecture changes.
- Do not edit notes, templates, config, derivation files, context files, queues, methodology notes, or changelogs from this skill.
- Do not recommend broad restructuring from a single weak signal; prefer a smaller follow-up or an observation.
- Destructive, broad, or content-moving changes require explicit user approval in a separate implementation step.
- Use Codex file workflows and explicit user intent.
