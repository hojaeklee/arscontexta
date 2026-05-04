---
name: hippocampusmd-ask
description: Use when the user asks Codex questions about HippocampusMD methodology, knowledge-system design, vault architecture, or why/how a HippocampusMD workflow works.
---

# HippocampusMD Ask

Answer HippocampusMD methodology questions from local sources first. This skill is read-only: explain, cite, and suggest follow-up, but do not edit vault or plugin files.

## When Invoked

1. Treat the current working directory as the context unless the user gives another path.
2. Classify the question to choose search targets:
   - `why`: principles, trade-offs, research grounding.
   - `how`: workflow mechanics and operational guidance.
   - `what`: examples, presets, and concrete vault shapes.
   - `compare`: trade-offs between methods or configurations.
   - `diagnose`: failure modes, friction, or unexpected behavior.
   - `configure`: dimension choices, vocabulary, schemas, or presets.
   - `evolve`: when and how a system should adapt.
3. Search with `rg` and read local files before using optional semantic tooling.

## Source Order

In the plugin repo, search these first:

- `plugins/hippocampusmd/reference/`
- `plugins/hippocampusmd/methodology/`
- `README.md`
- relevant `plugins/hippocampusmd/skills/` docs

In a HippocampusMD vault, search these first when present:

- `ops/derivation.md`
- `ops/methodology/`
- `manual/`
- `self/`
- relevant markdown notes under the configured notes directory

Use QMD, semantic search, or indexed knowledge tools only when they are already available in the current runtime. When answering methodology questions, state the scale policy clearly: small or narrow vaults can operate with `rg` plus MOC/topic-map traversal, while large, cross-domain, research, or heavy-processing vaults require QMD or equivalent semantic search for full-quality duplicate detection and cross-vocabulary discovery. If the tool is unavailable, describe that as degraded mode rather than blocking the answer.
Never require them, and never present unavailable external tools as Codex requirements.

## Answer Shape

- Lead with the direct answer, not the search process.
- Ground claims in the local files you actually read.
- Cite local paths when useful, especially for methodology, reference, derivation, and manual files.
- Use the vault's vocabulary when `ops/derivation.md` or `ops/derivation-manifest.md` provides it.
- Note gaps honestly when the local methodology does not cover the question.
- Keep recommendations advisory; any file edits require a separate user-approved task.

## Boundaries

- Do not produce full architecture recommendation reports; use `hippocampusmd-recommend` when that port exists.
- Do not validate or mutate notes; use `hippocampusmd-validate`, `hippocampusmd-health`, or explicit editing tasks for those.
- Use Codex skill language and explicit user intent.
