---
name: arscontexta-refactor
description: Use when the user asks Codex to plan Ars Contexta vault restructuring after config, derivation, architecture, schema, navigation, or automation changes.
---

# Ars Contexta Refactor

Plan restructuring from a chosen architecture or configuration shift. Refactor compares live config against derivation state and produces a report-only restructuring plan by default.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Require both:
   - `ops/config.yaml` for current live configuration.
   - `ops/derivation.md` for original design baseline and rationale.
3. If either required file is missing, stop with: "Cannot refactor without both `ops/config.yaml` and `ops/derivation.md`."
4. Read `ops/derivation-manifest.md` when present for vocabulary, dimension names, platform hints, notes folder, inbox folder, and topic-map wording.
5. Recommend `arscontexta-architect` when no change rationale exists or the user is still deciding what should change.

## Modes

- all-dimension review: compare every core dimension and feature flag.
- single-dimension focus: inspect only the named dimension, while still checking cascades.
- `--dry-run`: show the restructuring plan and stop.
- report-only: default mode; produce a plan without making changes.

## Planning Workflow

- Compare dimensions such as granularity, organization, linking, processing, navigation, maintenance, schema, and automation.
- Compare feature flag state such as semantic search, processing pipeline, self space, session capture, and parallel workers when present.
- For every detected shift, identify affected artifacts, likely sections, content impact, risk, reversibility, estimated effort, and validation checks.
- Consult `reference/interaction-constraints.md` for interaction constraints before recommending cascaded changes.
- Flag hard blocks clearly and do not recommend proceeding until the configuration is adjusted.

## Output

- Produce a report-only restructuring plan with:
  - changed dimensions or feature flags
  - affected artifacts and proposed changes
  - content impact, including note moves, MOC restructuring, schema migrations, or wiki-link updates
  - risk and reversibility for each change
  - validation steps such as schema checks, wiki-link checks, MOC hierarchy checks, vocabulary checks, and session loading checks
- If no config-vs-derivation changes are detected, report the clean state and suggest `arscontexta-architect` for exploratory evolution advice.

## Approval Boundaries

- Require explicit approval before file moves, rewrites, content migrations, template edits, config/derivation updates, hook edits, or broad note changes.
- Do not auto-regenerate skills in this first Codex port; list affected skills and proposed updates instead.
- Do not automatically mutate `ops/queue/*`, run destructive migrations, or apply broad restructuring from this skill.
- Keep approved implementation steps small and inspectable, and validate after changes if the user separately approves implementation.
- Do not assume Claude slash-command invocation or Claude-only tools; use Codex file workflows.
