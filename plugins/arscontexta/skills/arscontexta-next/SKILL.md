---
name: arscontexta-next
description: Use when the user asks Codex what to do next, what the next best Ars Contexta action is, or how to prioritize vault work.
---

# Ars Contexta Next

Recommend one next action from bounded local vault signals. This skill recommends; it does not execute, mutate queues, or write logs.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Prefer the deterministic helper when available:

```bash
scripts/next-vault.sh . --limit 25 --format text
```

From an installed plugin package or repository development mirror, discover the helper relative to the plugin or repo root:

```bash
plugins/arscontexta/scripts/next-vault.sh . --limit 25 --format text
```

## Recommendation Rules

- Recommend exactly one action.
- Never execute the recommendation.
- Use only bounded local inspection.
- Read `ops/tasks.md`, queue files, inbox state, goals, observations, tensions, and recent health reports when present.
- Task stack items outrank automated signals.
- If no goals file exists and no task stack item is active, recommend creating goals before deeper automation.
- Early vaults need capture or processing more than maintenance.
- For noisy vaults, show only the 2-4 signals that explain the recommendation.
- Do not reconcile maintenance queues or write `ops/next-log.md` in this first Codex port.

## Output

Return:

- `State`: 2-4 decision-relevant signals.
- `Recommended`: one concrete command or action.
- `Rationale`: why this action matters and what degrades if it is deferred.
- Optional `After that`: only when recent recommendation history suggests repetition.

Keep the response compact. Avoid menus unless the user explicitly asks for alternatives.
