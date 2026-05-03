---
name: arscontexta-pipeline
description: Use when the user asks Codex to process one local source end to end through the Ars Contexta queue, plan source processing, or inspect resumable pipeline status.
---

# Ars Contexta Pipeline

Pipeline is an orchestration skill, not a new queue engine. It coordinates `arscontexta-seed`, `arscontexta-ralph`, and the phase skills to process one local source through the queue with visible, resumable state.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Require plan/status before processing. Show a plan for a source or status for an existing batch before running phase work.
3. Prefer the deterministic helper for planning and status:
   - repo development: `scripts/pipeline-vault.sh [vault-path] --plan --file PATH --format text|json`
   - installed plugin: `plugins/arscontexta/scripts/pipeline-vault.sh [vault-path] --status --batch ID --format text|json`
4. Keep all queue state under `ops/queue/`. Do not create hidden pipeline state.

## Phase Partners

Coordinate existing Codex-native skills:

- `arscontexta-seed` creates or detects the source batch.
- `arscontexta-ralph` inspects, dry-runs, and advances queued phases.
- `arscontexta-reduce` handles extract work from source material.
- `arscontexta-reflect` handles forward connection discovery.
- `arscontexta-reweave` handles backward-link and older-note repair.
- `arscontexta-verify` handles final quality gating.
- `arscontexta-archive-batch` handles final completed-batch archival.

The pipeline should call these skills conceptually and report the exact next command. It should not duplicate their internal behavior.

## Codex subagent constraints

Do not perform hidden background work. Use Codex subagents only when the user explicitly asks for processing or when the host workflow clearly supports subagent execution.

- If subagents are not explicitly requested or clearly available, stop at a runnable plan.
- If processing is requested, use `arscontexta-ralph` as the explicit queue worker.
- Do not process claims inline in the lead session.
- Report each phase boundary and queue state before continuing.

## Failure Handling

Use explicit failure reporting and resumability guidance throughout the workflow.

Do not hide failures. After each phase, report:

- phase result
- pending, active, blocked, and done counts
- incomplete or blocked tasks
- next resumable command, usually `arscontexta-ralph --batch ID`

If a phase fails, stop and show how to resume. Queue state is the source of truth, so the user can continue later from the current batch status.

## Archive Boundary

When all batch tasks are done, report ready-to-archive status and recommend `arscontexta-archive-batch --batch ID`. Pipeline should not move task files or generate archive summaries directly; final cleanup belongs to `arscontexta-archive-batch`.

## Output Expectations

For a source plan, show source path, batch id, whether it is unseeded or already queued, and the next seed/Ralph command.

For batch status, show queue file, counts, phase distribution, blocked tasks, ready-to-archive state, and next action.

## Boundaries

- Pipeline coordinates a small source end to end; it is not an unattended daemon.
- Pipeline does not replace `arscontexta-ralph`.
- Pipeline does not create notes directly or mutate queue state outside `ops/queue/`.
- Use Codex file workflows, explicit user intent, and visible phase reports.
