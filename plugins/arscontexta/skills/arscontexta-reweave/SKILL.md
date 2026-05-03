---
name: arscontexta-reweave
description: Use when the user asks Codex to revisit older Ars Contexta notes, add backward links, repair sparse notes, or update notes with newer vault context.
---

# Ars Contexta Reweave

Revisit existing notes with newer vault context. Reweave is the backward pass: it asks what would be different if this note were written today, then proposes focused updates without broad churn.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary such as notes folder, note name, reweave verb, topic map/MOC wording, and suggested next-step command names.
   - `ops/config.yaml` for processing depth, chaining, reweave scope, notes directory, and template defaults.
3. Accept targets as:
   - a specific note
   - `sparse` notes with few connections
   - `recent` notes or `--since Nd`
   - no argument, which means discover candidate notes by age, sparse links, or outdated context
4. Read target notes fully before proposing changes.

## Discovery Workflow

- Use local search before semantic tooling.
- Start with file age, frontmatter topics, existing wiki links, backlinks, relevant MOCs/topic maps, and `rg` across the configured notes folder.
- Follow wiki-link and MOC/topic-map traversal to compare the target against newer related notes.
- Use QMD or equivalent semantic search when it is available. For large, cross-domain, research, or heavy-processing vaults, missing semantic search means reweave is running in degraded mode; continue with `rg` and MOC/topic-map traversal, but report that cross-vocabulary newer-context discovery is incomplete.
- Keep a concise discovery trace: which notes, MOCs/topic maps, backlinks, ages, and searches informed the proposal.

## Reweave Evaluation

- Ask: "If I wrote this note today, with everything now in the vault, what would be different?"
- Evaluate backward links to newer notes, claim sharpening, description improvement, split candidates, contradiction signals, and tension signals.
- Prefer small improvements: add useful context, strengthen traversal, clarify descriptions, or propose a split.
- Reject churn that only restyles prose or adds vague "related" links.

## Write Behavior

- Default to report-only proposals unless the user explicitly asks to edit immediately.
- With approval, make focused inline wiki-link edits, contextual `relevant_notes` entries, description improvements, or small prose edits.
- Require separate approval before substantial rewrites, splits, or claim changes.
- Preserve existing note voice and avoid broad churn.
- After edits, recommend running `arscontexta-validate` on changed notes.

## Boundaries

- Do not automatically mutate `ops/queue/*`, emit Ralph handoff blocks, or perform pipeline task updates.
- Do not create `ops/observations/` or `ops/tensions/` side-effect files unless the user separately asks.
- Use Codex file workflows and explicit user intent.
