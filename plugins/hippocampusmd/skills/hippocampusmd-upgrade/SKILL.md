---
name: hippocampusmd-upgrade
description: Use when the user asks Codex to compare an existing HippocampusMD vault against current plugin methodology, check generated skill practices, or plan upgrades.
---

# HippocampusMD Upgrade

Compare installed/generated vault practices against the current plugin methodology. Upgrade is advisory by default: it produces an upgrade plan before any file changes.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for vocabulary, platform hints, notes folder, and generated command names.
   - `ops/config.yaml` for current dimensional positions and processing settings.
   - `ops/derivation.md` for derivation state, engine version, and domain context.
   - `ops/generation-manifest.yaml` for generation timestamps, skill versions, and plugin version when available.
3. Choose the target scope:
   - all generated skills when no target is given.
   - `--all` for all generated skills.
   - one named skill when the user names a specific generated skill.

## Inventory

- Inventory installed/generated vault skills and record version, generated-from metadata, and missing frontmatter when visible.
- Detect user-modified skill files where possible with git status or local modification evidence.
- Treat missing generation manifests as unknown version state, not as failure.
- Keep plugin/meta-skill updates separate; plugin/meta-skill updates remain a plugin release concern.

## Methodology Consultation

- Compare methodology and practice against local plugin `plugins/hippocampusmd/methodology/` and `plugins/hippocampusmd/reference/` sources.
- Prefer methodology comparison, not hash comparison: hashes only show file differences, while upgrade analysis asks whether the skill approach still reflects current knowledge.
- Classify each finding as current, enhancement, correction, or extension.
- For user-modified skills, determine whether the user change already covers the improvement, can coexist with it, or conflicts with it.

## Output

- Present an upgrade plan with rationale, research or methodology grounding, local file references, risk, reversibility, and user-modification notes.
- Include side-by-side detail for user-modified skills when an upgrade would touch the modified area.
- Group the same conceptual change across multiple skills instead of repeating it noisily.
- If no improvements are found, report that checked skills reflect current practices.

## Approval Boundaries

- Require explicit approval before any skill rewrite, methodology update, archive creation, generation-manifest update, or broad vault change.
- Never silently overwrite user-modified skills.
- Archive current skill versions before any separately approved rewrite.
- Direct broader architecture changes to `hippocampusmd-architect`, `hippocampusmd-refactor`, or `hippocampusmd-reseed`.
- Use Codex file workflows and explicit user intent.
