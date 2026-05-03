---
name: arscontexta-seed
description: Use when the user asks Codex to add a source file to an Ars Contexta processing queue, seed an inbox item, or prepare a source for later reduce, ralph, or pipeline processing.
---

# Ars Contexta Seed

Seed adds one local source file to the processing queue. It prepares deterministic queue state without running extraction, Ralph workers, or the broader pipeline.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Read vocabulary and path hints from `ops/derivation-manifest.md`, `ops/derivation.md`, and `ops/config.yaml` when present.
3. Require a local file path. If the user provides no path, inspect the configured inbox and ask which file to seed.
4. Prefer the bundled helper:
   - `plugins/arscontexta/scripts/seed-vault.sh [vault-path] --file PATH --format text|json`

## Helper Behavior

The helper should:

- resolve explicit paths first, then configured inbox paths
- reject URLs and non-file targets
- check active queue files, task files, and `ops/queue/archive/` for duplicate sources
- avoid duplicates by default and report duplicate matches without mutating queue state
- create `ops/queue/archive/YYYY-MM-DD-source-name/`
- Move sources only when they are inside the configured inbox
- Living docs outside inbox stay in place
- create an extract task file under `ops/queue/`
- ensure queue state stays under `ops/queue/`
- prefer the existing queue format among `ops/queue/queue.json`, `ops/queue/queue.yaml`, and `ops/queue.yaml`
- compute `next_claim_start` from both queue state and archive/task filenames

## Output Expectations

Report:

- source id and original source path
- whether the source moved
- archive folder and task file
- queue file updated
- line count and content type
- `next_claim_start`
- duplicate status when applicable
- next steps for `arscontexta-ralph` or `arscontexta-pipeline`

File moves and archive writes must be clearly reported. Always avoid overwriting user content; if a task file, archive destination, or queue entry collides, stop or choose a non-overwriting archive folder and report it.

## Boundaries

- Seed prepares queue state only; it does not extract notes.
- Keep queue state under `ops/queue/`; do not write hidden state elsewhere.
- Do not run `arscontexta-ralph`, `arscontexta-pipeline`, or downstream processing automatically.
- Do not move living documents outside the configured inbox.
- Use Codex file workflows, local inspection, and deterministic helper output.
