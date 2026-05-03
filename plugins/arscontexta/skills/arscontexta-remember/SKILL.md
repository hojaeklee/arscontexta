---
name: arscontexta-remember
description: Use when the user asks Codex to capture Ars Contexta learnings, corrections, preferences, friction, session patterns, methodology notes, observations, or tensions.
---

# Ars Contexta Remember

Capture durable local learning without overreaching. Remember turns explicit user guidance or confirmed session patterns into scoped vault methodology, observations, or tensions.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary and domain context.
   - `ops/config.yaml` for self-evolution thresholds and related settings.
   - existing `ops/methodology/`, `ops/observations/`, and `ops/tensions/` notes before proposing new writes.
3. Choose the smallest mode that fits the request:
   - explicit mode: the user directly describes a learning, correction, preference, or friction.
   - contextual mode: inspect recent conversation corrections and ask confirmation before writing.
   - session-mining mode: scan `ops/sessions/` for repeated patterns and ask confirmation before writing mined learnings.

## Classification

- Methodology notes go in `ops/methodology/` when the learning is a clear, durable behavior rule.
- Observations go in `ops/observations/` when a pattern is uncertain, early, or needs more evidence.
- Tensions go in `ops/tensions/` when the learning reveals a contradiction, unresolved conflict, or competing methodology pressure.
- Update `ops/methodology.md` only when creating or extending methodology notes.

## Write Behavior

- Explicit user-provided learnings may be written after confirming the intended wording and scope.
- Contextual and session-mined learnings require user confirmation before any file write.
- Prefer extending existing notes when the learning is already covered; create a new note only when it is meaningfully distinct.
- Keep every captured note specific, scoped, and actionable, with clear what-to-do, what-to-avoid, why-it-matters, and scope when writing methodology.

## Boundaries

- Do not automatically mutate `ops/queue/*`, emit Ralph handoff blocks, or perform pipeline task updates.
- Do not rewrite broad system behavior, context files, or plugin source; defer broader adaptation to rethink, refactor, or later evolution workflows.
- Use Codex file workflows and explicit user intent.
