---
name: arscontexta-reduce
description: Use when the user asks Codex to extract durable Ars Contexta notes from source files, inbox items, pasted source material, or raw research/content.
---

# Ars Contexta Reduce

Extract durable, domain-relevant notes from source material. This workflow may write notes only when the user explicitly approves note creation or asks for immediate note writing.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary such as notes folder, inbox folder, note name, reduce verb, topic map wording, and next-step command names.
   - `ops/config.yaml` for processing depth, chaining, selectivity, templates, and notes directory defaults.
3. Accept source material as:
   - explicit source file paths
   - inbox processing requests from the configured inbox folder
   - pasted source material in the conversation
4. Read the source fully before extracting. For large sources, chunk into bounded sections and keep one extraction report across chunks.

## Extraction Workflow

- Hunt for domain-relevant insights, reasoning, patterns, comparisons, tensions, anti-patterns, open questions, implementation ideas, validations, and useful enrichments.
- Bias toward capture for relevant sources. Skip only content that is off-topic, too vague, purely summary, or literally identical to an existing note.
- Check existing notes with `rg` before proposing new notes, and mark likely duplicates as enrichment candidates rather than silently skipping them.
- Produce an extraction report before note creation unless the user explicitly asked to write notes immediately.
- The report should include proposed note titles, extraction rationale, likely topics/wiki links, and any items intentionally skipped.

## Note Writing

When writing is approved:

- Write only under the configured notes folder, defaulting to `notes/`.
- Preserve domain vocabulary in note naming, process wording, and suggested next steps.
- Use local templates or `_schema` guidance when available.
- Write valid YAML frontmatter and stable wiki links.
- Include required fields from the applicable schema; when no schema exists, require `description` and `topics`.
- Keep notes atomic, readable, and useful without the original source open.
- After writing, recommend running `arscontexta-validate` on the created or changed notes.

## Boundaries

- Do not automatically mutate `ops/queue/*`, create Ralph handoff tasks, or perform pipeline handoff behavior.
- Do not create `ops/observations/` or `ops/tensions/` side-effect files unless the user separately asks.
- Use Codex file workflows and explicit user intent.
