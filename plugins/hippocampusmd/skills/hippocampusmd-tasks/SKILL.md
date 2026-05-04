---
name: hippocampusmd-tasks
description: Use when the user asks Codex to view or manage HippocampusMD task stack, discoveries, queue state, pending work, blocked work, or completed work.
---

# HippocampusMD Tasks

Show and explicitly manage the human task stack in `ops/tasks.md` while also reporting the read-only pipeline queue state.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Use the smallest operation that matches the request:
   - status, pending work, queue status: show combined task and queue view.
   - discoveries: show only the `Discoveries` section.
   - add: append one task to `Current`.
   - done: move a numbered current task to `Completed`.
   - drop: remove a numbered current task without completion history.
   - reorder: move a numbered current task to another position.
3. Prefer the deterministic helper when available:

```bash
plugins/hippocampusmd/scripts/tasks-vault.sh . --status --limit 25 --format text
plugins/hippocampusmd/scripts/tasks-vault.sh . --discoveries --limit 25 --format text
plugins/hippocampusmd/scripts/tasks-vault.sh . --add "Review inbox notes"
plugins/hippocampusmd/scripts/tasks-vault.sh . --done 1
plugins/hippocampusmd/scripts/tasks-vault.sh . --drop 2
plugins/hippocampusmd/scripts/tasks-vault.sh . --reorder 3 1
```

From an installed plugin package or the repository, discover the helper relative to the plugin or repo root:

```bash
plugins/hippocampusmd/scripts/tasks-vault.sh . --status --limit 25 --format text
```

## Safety

- Status and discoveries are read-only.
- Write operations modify only `ops/tasks.md`.
- Never mutate `ops/queue/*` from this skill. Queue state belongs to pipeline and runner skills.
- If a write operation is ambiguous, ask for the exact task number or description before running it.
- If `ops/tasks.md` is missing, create it only for an explicit add operation.

## Output

For status, report:

- Current, completed, and discovery items from `ops/tasks.md`.
- Queue counts split into pending, active, blocked, and completed.
- Queue task id, phase, target, and batch when available.
- Archivable batches when every task in a batch is completed, with `hippocampusmd-archive-batch` as the cleanup workflow.

Keep output bounded. Prefer concrete task names and file paths over broad commentary.
