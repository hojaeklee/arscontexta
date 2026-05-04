---
name: hippocampusmd-archive-batch
description: Use when the user asks Codex to archive a completed HippocampusMD processing batch, clean up completed queue task files, or finish the final pipeline archival phase.
---

# HippocampusMD Archive Batch

Archive Batch is deterministic queue cleanup for completed processing batches. It moves completed task files into the batch archive folder, writes a concise summary, and removes archived batch entries from active queue state.

## When Invoked

1. Treat the current directory as the vault unless the user gives another path.
2. Require an explicit batch id. If the user does not provide one, inspect queue status and ask which completed batch to archive.
3. Prefer the deterministic helper:
   - `plugins/hippocampusmd/scripts/archive-batch-vault.sh [vault-path] --batch ID --format text|json`
4. Use Codex file workflows and visible helper output; do not hide queue mutations.

## Preconditions

Apply the complete-batch precondition before any mutation:

- Read active queue state from `ops/queue/queue.json`, `ops/queue/queue.yaml`, or `ops/queue.yaml`.
- Select tasks where `id` equals the batch id or `batch` equals the batch id.
- Every selected task must have status `done` or `completed`.
- If no tasks match, or any selected task is pending, active, blocked, failed, or otherwise incomplete, stop without moving files, writing summaries, or editing queue state.

## Helper Behavior

The helper should:

- preserve JSON or YAML queue shape while removing archived batch entries, preserving queue format exactly where possible
- resolve the archive folder from the extract task's `archive_folder`
- fall back to `ops/queue/archive/YYYY-MM-DD-BATCH` when no archive folder is recorded
- move selected task files from `ops/queue/` into the archive folder
- enforce no overwrites for moved task files
- write `BATCH-summary.md`, using a numeric suffix only when the summary name already exists
- leave unrelated batches and their active task files untouched

## Summary

The summary should be concise and derived from queue/task metadata only. Include:

- batch id
- archive timestamp
- archive folder
- source path when recorded
- counts by task type
- archived task ids, task types, and targets

Do not inspect created notes, rewrite notes, or invent processing results that are not present in queue/task metadata.

## Output Expectations

Report:

- batch id
- task count archived
- task files moved
- archive folder
- summary path
- queue file updated

For JSON output, include equivalent machine-readable fields for downstream checks.

## Boundaries

- Do not process research directly. Do not extract notes. Do not verify claims, reflect links, reweave notes, or run Ralph workers.
- Do not archive incomplete batches.
- Do not overwrite existing files in the archive folder.
- Do not move source files or living documents.
- Do not mutate `ops/queue/*` outside the selected completed batch.
- Use Codex file workflows and deterministic helper output.
