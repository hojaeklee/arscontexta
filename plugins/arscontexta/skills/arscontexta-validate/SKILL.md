---
name: arscontexta-validate
description: Use when the user asks Codex to validate Ars Contexta notes, schemas, frontmatter, enum values, descriptions, relevant_notes, or wiki link health.
---

# Ars Contexta Validate

Run detailed, read-only schema validation for an Ars Contexta or Obsidian markdown vault. This is stricter than `arscontexta-session validate` and is meant for deliberate note quality checks.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Choose the smallest useful target:
   - A named note or file path: validate that file.
   - "changed", "recent changes", or "my edits": validate the bounded git changed set.
   - "all notes" or "the vault": validate `notes/` only.
3. Prefer the deterministic helper when available:

```bash
scripts/validate-vault.sh . --file notes/example.md --limit 25 --format text
scripts/validate-vault.sh . --changed --limit 25 --format text
scripts/validate-vault.sh . --all --limit 25 --format text
```

From an installed plugin package or the repository development mirror, discover the helper relative to the plugin or repo root:

```bash
plugins/arscontexta/scripts/validate-vault.sh . --changed --limit 25 --format text
```

## What It Checks

- YAML frontmatter delimiters, parseability, duplicate top-level keys, and fields outside the active template schema.
- Required fields from template `_schema.required`, falling back to `description` and `topics`.
- Enum values from template `_schema.enums`.
- Description quality: non-empty, roughly 50-200 characters, more informative than the title, single sentence, and no trailing period.
- Topic links, body wiki links, and `relevant_notes` links by vault filename.
- Wiki links inside inline code or fenced code blocks are examples and should be ignored.
- `relevant_notes` should use `[[note]] -- relationship context`, not bare links.

## Safety

- Validation is read-only. Do not edit notes unless the user explicitly asks for fixes after seeing the report.
- Validation is non-blocking. `FAIL` means required validation rules were not met, but capture should not be prevented.
- Report concrete fixes for every warning or failure that matters.
- If the helper is unavailable, perform a bounded manual check with `rg` and file reads, then say the helper was unavailable.

## Output

Summarize:

- Overall status: `PASS`, `WARN`, or `FAIL`.
- Files checked.
- Failures first, then warnings.
- Suggested fixes with exact file paths.

Keep reports bounded. If a vault has many issues, show representative examples and recommend validating a narrower set before making edits.
