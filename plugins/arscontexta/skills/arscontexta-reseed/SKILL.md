---
name: arscontexta-reseed
description: Use when the user asks Codex to analyze Ars Contexta structural drift, re-derive a vault architecture, or plan content-preserving system reseeding.
---

# Ars Contexta Reseed

Analyze whether an existing vault needs principled re-derivation rather than incremental refactoring. Reseed defaults to analysis/report mode and must preserve content.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation.md` for original design intent, dimension rationale, vocabulary, and coherence checks.
   - `ops/config.yaml` for current live configuration.
   - `ops/derivation-manifest.md` for vocabulary, platform hints, notes folder, inbox folder, and topic-map wording.
3. Use `--analysis-only` as an explicit analysis/report mode. Without it, still present analysis before any implementation discussion.
4. Direct smaller incremental changes to `arscontexta-architect` or `arscontexta-refactor`.

## Drift Triggers

- Consider reseed when dimension incoherence spans several areas, vocabulary mismatch has accumulated, three-space boundaries have dissolved, template divergence is substantial, or the MOC hierarchy no longer reflects actual topic structure.
- Inventory notes, MOCs, templates, self space, inbox, ops files, health history, observations, tensions, and methodology evidence before diagnosing drift.
- Classify each dimension as none, aligned, compensated, incoherent, or stagnant.
- Re-evaluate vocabulary, three-space boundaries, template divergence, MOC structure, and configuration coherence against current evidence.

## Reference Grounding

- Consult local `plugins/arscontexta/reference/` sources first:
  - `interaction-constraints.md`
  - `derivation-validation.md`
  - `three-spaces.md`
  - `failure-modes.md`
  - `dimension-claim-map.md`
  - `evolution-lifecycle.md`
  - `self-space.md`
  - `kernel.yaml`
- Use optional semantic tooling only when already available; never require it.
- Ground every proposed dimension change in vault evidence and local reference paths.

## Output

- Produce a re-derivation proposal with drift summary, proposed dimension changes, content impact, risk, rollback, and validation expectations.
- State clearly whether the recommendation is reseed, architect review, or refactor planning.
- Include content preservation checks for notes, memory, and user content.
- Include validation expectations for kernel checks, link health, schema compliance, vocabulary consistency, MOC reachability, and three-space boundaries.

## Content Preservation

- Reseed never deletes notes, memory, or user content.
- If any proposed action could cause content loss, stop and warn the user.
- Preserve `self/` identity and memory unless the user explicitly approves a focused self-space update.
- Prefer reversible changes and name rollback paths before implementation.

## Approval Boundaries

- Require explicit approval before restructuring, folder moves, template edits, derivation rewrites, MOC changes, self-space updates, or broad note edits.
- Do not automatically apply the re-derived architecture, mutate `ops/queue/*`, regenerate skills, rewrite vault content, or run destructive migrations in this first Codex port.
- Use Codex file workflows and explicit user intent.
