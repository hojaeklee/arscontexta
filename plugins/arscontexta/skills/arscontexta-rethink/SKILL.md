---
name: arscontexta-rethink
description: Use when the user asks Codex to review accumulated Ars Contexta observations, tensions, methodology drift, or evidence-backed system evolution proposals.
---

# Ars Contexta Rethink

Review accumulated operational evidence and propose system changes. Rethink is evidence analysis first: it produces a proposal-only report unless the user explicitly approves implementation.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary, domain context, note naming, topic-map wording, and follow-up skill names.
   - `ops/config.yaml` for self-evolution thresholds, processing preferences, and enabled feature signals.
   - existing `ops/methodology/`, `ops/observations/`, and `ops/tensions/` notes as the local evidence base.
3. Choose the smallest mode that fits the request:
   - full review: drift check, evidence triage, pattern detection, and proposals.
   - `triage`: classify pending observations and tensions only.
   - `patterns`: analyze existing evidence for recurring themes.
   - `drift`: compare methodology notes against configuration, context, and current behavior.
   - single-file evidence review: inspect one observation or tension and recommend a disposition.

## Evidence Review

- Classify each evidence item as exactly one of: promote, methodology update, implementation proposal, archive or dissolve, or keep pending.
- Promote only durable domain insight that belongs as a normal note.
- Use methodology update for agent behavior guidance that should extend or create `ops/methodology/` notes.
- Use implementation proposal for concrete changes to configuration, context, templates, skills, or other system files.
- Archive or dissolve session-specific, superseded, or resolved evidence.
- Keep pending when the evidence is plausible but too thin to act on.

## Pattern Detection

- Do not fabricate patterns from isolated evidence.
- Treat three or more related observations or tensions as the normal minimum for a recurring pattern.
- Group evidence by category, referenced files, linked notes, affected workflow step, methodology category, and repeated contradiction.
- Report confidence, impact, and what would degrade if the pattern is deferred.
- If evidence suggests architecture-level change, recommend `arscontexta-architect`, `arscontexta-refactor`, or `arscontexta-reseed` rather than broad automatic edits.

## Output

- Produce a concise triage and proposal-only report by default.
- For each recommendation, cite local evidence paths from `ops/observations/`, `ops/tensions/`, or `ops/methodology/`.
- Separate evidence, current assumption, proposed change, expected benefit, risk, reversibility, and proposed scope.
- Ask for explicit user approval before any file write.

## Boundaries

- Do not perform note, methodology, config, context, changelog, or status edits without explicit approval.
- Do not automatically mutate `ops/queue/*`, emit Ralph handoff blocks, or alter pipeline state.
- Do not treat low-evidence impressions as system changes; capture them as observations instead.
- Do not assume Claude slash-command invocation or Claude-only tools; use Codex file workflows.
