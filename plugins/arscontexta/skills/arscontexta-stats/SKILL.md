---
name: arscontexta-stats
description: Use when the user asks Codex for Ars Contexta vault statistics, graph metrics, growth, link density, inbox state, queue state, or a shareable snapshot.
---

# Ars Contexta Stats

Show a concise, read-only snapshot of vault growth and health. Metrics are evidence, not judgment; detailed remediation belongs to health, graph, or processing skills.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Prefer the deterministic helper when available:

```bash
scripts/stats-vault.sh . --limit 25 --format text
scripts/stats-vault.sh . --share --format text
scripts/stats-vault.sh . --format json
```

From an installed plugin package or repository development mirror, discover the helper relative to the plugin or repo root:

```bash
plugins/arscontexta/scripts/stats-vault.sh . --limit 25 --format text
```

## What It Reports

- Knowledge graph size, MOCs, wiki-link count, average links, topics, and graph density.
- Health snapshot: orphans, dangling links, and schema compliance.
- Pipeline snapshot: inbox count, oldest inbox age, and queue state when present.
- Growth this week from `created:` frontmatter.
- System state: self space, methodology notes, observations, tensions, sessions, and health reports.

## Safety

- Read-only. Do not create history files or mutate queue/task state.
- Keep output concise and shareable.
- For large vaults, prefer approximate bounded metrics and recommend `arscontexta-graph` for precise graph analysis.
- Skip missing optional directories without treating them as failures.

## Output

Default output is a compact stats block plus only notable interpretation notes. `--share` produces a positive markdown snapshot suitable for sharing.
