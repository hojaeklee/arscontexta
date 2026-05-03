---
name: arscontexta-ralph
description: Use when the user asks Codex to inspect or process Ars Contexta queue tasks, run queued phases, dry-run queue work, or mark queue tasks advanced or blocked.
---

# Ars Contexta Ralph

Ralph is the standalone queue worker for Ars Contexta. Keep it separate from `arscontexta-pipeline`: Ralph executes explicit queue work, while `arscontexta-pipeline` will later decide when and how to orchestrate it.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Start with dry-run or report-only planning before processing queue tasks.
3. Prefer the deterministic helper for queue inspection and queue-state mutation:
   - `plugins/arscontexta/scripts/ralph-vault.sh [vault-path] --dry-run --limit N --format text|json`
4. Keep all queue processing state under `ops/queue/`.

## Helper Responsibilities

Use the helper for deterministic queue inspection and queue-state mutation only. It may:

- read `ops/queue/queue.json`, `ops/queue/queue.yaml`, or `ops/queue.yaml`
- summarize pending, active, blocked, and done tasks
- select pending tasks by limit, batch, and current phase
- advance a task after a successful worker phase
- block a task with a reason after a failed worker phase

The helper must not spawn agents, process source content, edit notes, or run downstream skills.

## Codex subagent rules

There must be no hidden background work and no inline task execution by the lead session. Ralph's lead session plans, spawns, evaluates, and advances queue state.

- Dry-run output must be shown before processing.
- In serial mode, use one bounded phase per spawned worker.
- A worker handles exactly the selected phase and then reports back.
- Advance queue state only after reviewing the worker result.
- If a worker fails, use the helper to mark the task blocked with the reason; do not retry automatically.
- Use parallel mode only when the user explicitly asks for parallel or subagent work.

## Phase Partners

Ralph coordinates existing Codex skills by phase:

- `arscontexta-seed` creates extract queue entries.
- `arscontexta-reduce` handles extract work from source material.
- `arscontexta-reflect` handles forward connection discovery.
- `arscontexta-reweave` handles backward-link and older-note repair.
- `arscontexta-verify` handles final quality gating.

For create or enrich phases, give the worker the queue task file, target, current phase, and one-phase-only constraint. Keep edits bounded to the worker's assigned task.

## Output Expectations

Report:

- queue file and selected tasks
- total, pending, active, blocked, and done counts
- phase distribution
- estimated Codex subagent spawns
- each worker result before queue advancement
- queue updates made by `--advance` or `--fail`
- remaining pending work and next suggested Ralph command
- completed batches that are ready for `arscontexta-archive-batch`

## Boundaries

- Ralph is not a background daemon.
- Ralph does not mutate queue state invisibly.
- Ralph does not replace `arscontexta-pipeline`; it is the explicit queue worker that pipeline may call later.
- Do not process non-pending tasks.
- Use Codex file workflows, local inspection, explicit user intent, and bounded subagent orchestration.
