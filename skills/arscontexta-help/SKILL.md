---
name: arscontexta-help
description: Use when the user asks what Ars Contexta can do, how to use this vault, how to use the plugin repo, what to do next, or asks for Ars Contexta help in Codex.
---

# Ars Contexta Help

Give concise, context-aware guidance for Ars Contexta in Codex. Explain what is available now, what is still being ported, and the single most useful next action.

## When Invoked

1. Treat the current working directory as the target context unless the user gives another path.
2. Detect the context with light inspection only:
   - Plugin repo: `.agents/plugins/marketplace.json`, `plugins/arscontexta/.codex-plugin/plugin.json`, or this repo README exists.
   - Ars Contexta vault: `.arscontexta` exists.
   - Obsidian-style vault: markdown files and vault-like directories exist, but `.arscontexta` is absent.
   - Generic directory: none of the above.
3. Do not run health scans, schema validation, dangling-link checks, or queue analysis. If the user wants diagnostics, recommend `arscontexta-health`.

## Context Responses

### Plugin Repo

Explain that this is the Ars Contexta plugin source, with Claude support preserved and Codex support being ported incrementally.

Available now:

- `arscontexta-help`: contextual orientation for Codex.
- `arscontexta-health`: quick vault health checks.
- `arscontexta-setup`: minimal Codex-native vault scaffolding.
- `scripts/vault-health.sh`: bounded link-health helper.
- `scripts/setup-vault.sh`: deterministic minimal setup helper.
- `arscontexta-validate`: detailed read-only note/schema validation.
- `arscontexta-tasks`: task stack and queue-state visibility for Codex.
- `arscontexta-next`: one read-only recommendation for what to do next.
- `arscontexta-stats`: concise vault metrics and shareable graph snapshots.
- `arscontexta-graph`: bounded graph diagnostics for orphans, hubs, sparse areas, and synthesis opportunities.
- `arscontexta-ask`: source-grounded methodology Q&A for Codex.
- `arscontexta-recommend`: read-only architecture advice for new vault use cases.
- `scripts/check-codex-plugin.sh` and `scripts/check-vault.sh`: Codex compatibility smoke tests.

Planned or in migration:

- full setup and derivation parity
- ask and recommendation workflows
- processing pipeline skills
- maintenance and evolution skills beyond health

Recommend one next action:

- Run `scripts/check-codex-plugin.sh` after plugin edits or Codex updates.
- Run `scripts/check-vault.sh <vault-path>` before testing against a real vault.
- Continue the next GitHub migration issue if the repo checks are clean.

### Ars Contexta Vault

Explain that the directory is an Ars Contexta vault: markdown notes, wiki links, `ops/` state, and optional `self/` memory.

Available now in Codex:

- Ask for Ars Contexta help to orient yourself.
- Run `arscontexta-health` to check vault structure, schema signals, links, orphans, queues, and health state.
- Run `arscontexta-setup` to create or complete minimal Codex vault scaffolding.
- Run `arscontexta-validate` to check note frontmatter, schema fields, descriptions, enums, and wiki links.
- Run `arscontexta-tasks` to inspect or explicitly update `ops/tasks.md`.
- Run `arscontexta-next` to get one bounded, rationale-backed next action.
- Run `arscontexta-stats` to summarize graph size, health, growth, and pipeline state.
- Run `arscontexta-graph` to inspect graph structure and connection opportunities.
- Run `arscontexta-ask` for source-grounded answers about Ars Contexta methodology.
- Run `arscontexta-recommend` for research-backed architecture advice before setup.
- Use the manual if `manual/` exists.

Planned or in migration:

- full setup parity
- query and recommendation skills
- reduce, reflect, reweave, verify, and pipeline skills
- richer maintenance and evolution skills

Recommend one next action:

- If the user asks "what should I do next", suggest running `arscontexta-health`.
- If `manual/getting-started.md` exists, mention it as the best human-readable orientation.
- If `manual/` exists but no getting-started page is obvious, mention browsing `manual/`.

### Obsidian-Style Vault Without Ars Contexta

Explain that this looks like a markdown vault, but Ars Contexta configuration was not detected.

Recommend one next action:

- If the user wants diagnostics anyway, run `arscontexta-health` as a generic Obsidian-vault check.
- If the user wants Ars Contexta structure, recommend `arscontexta-setup` for minimal Codex scaffolding and note that full Claude setup parity is still being ported.

### Generic Directory

Explain that Ars Contexta works best when Codex is opened in either:

- the Ars Contexta plugin repo, or
- an Ars Contexta or Obsidian markdown vault.

Recommend one next action:

- Open Codex in the vault directory.
- Or install/enable the local plugin from the Agentic Note Taking marketplace if that has not been done.

## Response Rules

- Give one recommended next action, not a long menu.
- Use Codex language: "ask Codex", "run the health skill", "open this vault".
- Do not present Claude slash commands as Codex commands.
- Mention Claude commands only when explaining that they exist in Claude Code, not Codex.
- Keep the response shorter than the Claude help skill and avoid full command catalogs.
- Prefer concrete local paths when they are obvious.
