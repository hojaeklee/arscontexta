---
name: arscontexta-reflect
description: Use when the user asks Codex to find meaningful connections between Ars Contexta notes, weave wiki links, or update topic maps/MOCs.
---

# Ars Contexta Reflect

Find meaningful connections between notes and, with approval, weave focused links into notes or topic maps. This is a semantic workflow: every connection must explain why traversal between the notes helps.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary such as notes folder, note name, reflect verb, topic map/MOC wording, and suggested next-step command names.
   - `ops/config.yaml` for processing depth, chaining, notes directory, and template defaults.
3. Accept targets as:
   - a specific note
   - a topic area or MOC/topic map
   - `recent` or `new` notes
   - a user-selected set of notes
4. Read target notes fully before proposing links.

## Discovery Workflow

- Use local search before optional semantic tooling.
- Start with frontmatter topics, existing wiki links, backlinks, relevant MOCs/topic maps, and `rg` across the configured notes folder.
- Follow wiki-link traversal from promising candidates to understand the neighborhood.
- Optional QMD or semantic search may be used only when already available; never require it.
- Keep a concise discovery trace: which notes, MOCs/topic maps, backlinks, and searches informed the report.

## Connection Standard

- Apply the articulation test to every proposed connection: `[[note A]] connects to [[note B]] because ...`.
- Accept links that extend, ground, contradict, exemplify, synthesize, or enable another note.
- Reject links that are merely "related", keyword-only, or likely to confuse future traversal.
- Flag synthesis opportunities in the report, but do not create synthesis notes during reflect unless the user asks separately.

## Write Behavior

- Produce a connection report before editing unless the user explicitly asks to edit immediately.
- With approval, edit only focused inline wiki links, contextual `relevant_notes` entries, or MOC/topic-map additions.
- Preserve existing note voice and avoid broad rewrites.
- Keep edits local to the target notes and directly relevant MOCs/topic maps.
- After edits, recommend running `arscontexta-validate` on changed notes.

## Boundaries

- Do not automatically mutate `ops/queue/*`, emit Ralph handoff blocks, or perform pipeline task updates.
- Do not create `ops/observations/` or `ops/tensions/` side-effect files unless the user separately asks.
- Use Codex file workflows and explicit user intent.
