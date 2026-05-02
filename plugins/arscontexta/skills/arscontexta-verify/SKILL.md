---
name: arscontexta-verify
description: Use when the user asks Codex to verify Ars Contexta note quality, schema/frontmatter validity, wiki-link health, topic-map integration, or changed-note readiness.
---

# Ars Contexta Verify

Run a bounded quality gate for one note, recent notes, or a small changed set. Verify summarizes actionable findings; it is not an auto-fixer.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary such as notes folder, note name, verify verb, topic map/MOC wording, templates path, and follow-up command names.
   - `ops/config.yaml` for verification settings, processing depth, notes directory, and templates defaults.
3. Accept targets as:
   - a specific note
   - `recent` notes
   - a small changed set
4. Keep checks bounded. Do not dump noisy whole-vault output.

## Verification Workflow

- Use `scripts/validate-vault.sh` or `plugins/arscontexta/scripts/validate-vault.sh` when available for deterministic schema/frontmatter, description, enum, wiki-link, and `relevant_notes` validation.
- Combine helper output with a Codex review of description quality, topic-map/MOC integration, sparse/orphan risk, and obvious health issues.
- Use local `rg`, wiki-link traversal, backlinks, and bounded graph/health helpers before optional semantic tooling.
- Optional QMD or semantic search may be used only when already available; never require it.

## Findings

- Report `PASS`, `WARN`, and `FAIL` findings with short, actionable explanations.
- Description quality checks should cover presence, specificity, whether the description adds information beyond the title, and whether it predicts the note content.
- Schema/frontmatter checks should cover YAML validity, required fields, unknown fields, enum values, and `description`/`topics` defaults when no schema is present.
- Wiki-link checks should include body links, topics, and `relevant_notes`, while ignoring code examples when helper output supports that.
- Topic-map/MOC integration should confirm the note is meaningfully discoverable from at least one relevant topic map when applicable.
- Sparse/orphan risk should recommend connection work rather than failing otherwise valid notes.

## Output

- Summarize only the findings relevant to the target note or changed set.
- Recommend `arscontexta-reflect` for missing connections, `arscontexta-reweave` for stale or sparse older notes, and `arscontexta-validate` for deterministic schema/link follow-up.
- Do not edit notes by default.

## Boundaries

- Do not automatically edit notes, mutate `ops/queue/*`, emit Ralph handoff blocks, or perform pipeline task updates.
- Do not create `ops/observations/` or `ops/tensions/` side-effect files unless the user separately asks.
- Do not assume Claude slash-command invocation or Claude-only tools; use Codex file workflows.
