---
name: arscontexta-graph
description: Use when the user asks Codex for Ars Contexta graph analysis, graph health, orphans, hubs, sparse notes, broken links, or synthesis opportunities.
---

# Ars Contexta Graph

Run bounded, read-only graph diagnostics for an Ars Contexta markdown vault. This skill goes deeper than `arscontexta-stats` by naming specific graph structures and next actions.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Select the smallest useful mode:
   - `health`: density, orphans, dangling links, MOC coverage, MOC sizes.
   - `hubs`: authorities, hubs, and synthesizer notes.
   - `sparse`: low-link notes and isolated components.
   - `triangles`: open triads that may indicate synthesis opportunities.
3. Prefer the deterministic helper when available:

```bash
scripts/graph-vault.sh . --mode health --limit 25 --format text
scripts/graph-vault.sh . --mode hubs --limit 10 --format text
scripts/graph-vault.sh . --mode sparse --limit 25 --format text
scripts/graph-vault.sh . --mode triangles --limit 10 --format text
```

From an installed plugin package or repository development mirror, discover the helper relative to the plugin or repo root:

```bash
plugins/arscontexta/scripts/graph-vault.sh . --mode health --limit 25 --format text
```

## Safety

- Read-only. Do not create graph caches, update queue files, or edit notes.
- Keep output bounded and interpreted; do not dump raw graph edges.
- For large vaults, accept approximate metrics and recommend narrower follow-up analysis.
- Suggested repairs are recommendations only.

## Output

Report findings with concrete note names, short descriptions when available, and one or two specific actions such as running `arscontexta-graph --mode sparse`, `reflect`, or `reweave`.
