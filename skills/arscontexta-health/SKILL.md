---
name: arscontexta-health
description: Use when the user asks Codex to check, diagnose, validate, or report on the health of an Ars Contexta or Obsidian markdown knowledge vault.
---

# Ars Contexta Health

Run a focused vault health check for an Ars Contexta markdown knowledge graph. Prefer concrete file counts, paths, and fixes over broad commentary.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. If the path contains `.arscontexta`, use it as an Ars Contexta vault.
3. If `.arscontexta` is absent, continue only when the directory still appears to be a markdown vault; state that Ars Contexta configuration was not detected.
4. If the user asks for `full` or `three-space`, load the relevant shared reference from `../../reference/three-spaces.md`. Otherwise keep the check quick.

## Quick Check

Prefer the bounded helper when it exists:

```bash
plugins/arscontexta/scripts/vault-health.sh . --mode quick --limit 25 --format text
```

When running from an installed plugin package or a vault, discover the helper relative to the Ars Contexta repository or plugin root if needed. The repository development mirror is:

```bash
scripts/vault-health.sh . --mode quick --limit 25 --format text
```

Quick health checks are read-only. Do not write `ops/health/YYYY-MM-DD-report.md` unless the user explicitly asks for a persisted report.

Collect:

- Vault marker and config: `.arscontexta`
- Core directories: `notes/`, `inbox/`, `ops/`, `self/`, `manual/`
- Derivation/config files: `ops/derivation-manifest.md`, `ops/derivation.md`, `ops/config.yaml`
- Markdown inventory: count `.md` files, excluding `.git/`
- Schema signals: missing YAML frontmatter, empty `description:`, missing `topics:`
- Link health: unresolved wiki links
- Orphans: notes with no incoming wiki links from other markdown files
- Queue and health state: `ops/queue/`, `ops/health/`, `ops/observations/`, `ops/tensions/`

Use `rg` and shell utilities for inventory. Avoid rewriting notes during diagnosis unless the user explicitly asks for fixes.

### Quick Check Safety

- Do not invoke `ops/scripts/graph/dangling-links.sh` directly during quick health.
- Do not run unbounded `rg`, `find`, or shell loops that print every unresolved link occurrence.
- If the bounded helper is unavailable, cap manual checks to summary counts plus at most 25 examples per category.
- If any command starts producing noisy output, stop using that command and report that the check was capped.
- Treat `ops/scripts/graph/` as an optional vault-generated graph-tool location only; do not assume older paths such as `ops/scripts/dangling-links.sh` exist.

For link health, distinguish where broken links appear:

- `primary`: `notes/`, `self/`, `manual/`, `inbox/`, and selected setup/config files under `ops/`
- `operational`: `ops/queue/`, `ops/health/`, `ops/sessions/`, `ops/observations/`, `ops/tensions/`, and similar state/history
- `noise`: docs, examples, templates, reference material, plugin source, and imported or legacy areas

Primary dangling links make link health `FAIL`. Operational dangling links are `WARN`. Noise-only dangling links should be reported separately and should not drive an overall `FAIL`.

## Report Format

Return a concise report with:

- Overall status: `PASS`, `WARN`, or `FAIL`
- What was checked
- Findings grouped by severity
- Specific files or directories involved
- Recommended next action

Use these levels:

- `FAIL`: primary broken links, unreadable configuration, missing required vault structure, or files that cannot be parsed safely
- `WARN`: missing frontmatter fields, stale orphans, sparse links, pending operational queues, or absent optional Ars Contexta config
- `PASS`: checked area has no actionable issue

## Full Check

For `full`, extend the quick check with:

- Description quality
- Three-space boundary issues between `self/`, content notes, and `ops/`
- Processing throughput signals from queues and session logs
- MOC coherence and sparse topic maps
- Stale notes or old inbox items

Load only the references needed for the requested check. The Claude skill at `../health/SKILL.md` can be used as a detailed compatibility reference, but do not copy its long command-style output unless the user asks for Claude parity.
