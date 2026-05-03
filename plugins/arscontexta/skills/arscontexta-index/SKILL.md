---
name: arscontexta-index
description: Use when the user asks Codex to index my vault, build or rebuild the vault index, check VaultIndex status, export the vault index, run an incremental scan, or inspect the persisted VaultIndex cache.
---

# Ars Contexta Index

Build, inspect, or export the persisted VaultIndex for an Ars Contexta vault without making the user remember helper paths.

## When Invoked

1. Treat the current working directory as the vault unless the user gives another path.
2. Resolve the deterministic helper from the plugin repository or installed plugin package:

```bash
plugins/arscontexta/scripts/vault-index.sh build . --format text
plugins/arscontexta/scripts/vault-index.sh status . --format text
plugins/arscontexta/scripts/vault-index.sh export . --format json
```

3. Choose the operation from the user's request:
   - "index my vault", "build the index", "rebuild the index", or "run an incremental scan" -> run `build`.
   - "show index status", "is the index fresh", or "VaultIndex status" -> run `status --format text`, unless JSON is requested.
   - "export the index" or "show index JSON" -> run `export --format json`.
4. After `build`, mention that the index is stored at `ops/cache/index.sqlite`.
5. Mention ignored-file counts when present; scan rules come from the user-editable `ops/config.yaml` `scan:` section.
6. If the vault is tracked in git, recommend ignoring `ops/cache/`.

## Safety

- `build` writes only `ops/cache/index.sqlite`.
- `status` and `export` are read-only.
- Scan rules only decide which markdown files are analyzed; ignored files are never deleted.
- Do not migrate or rewrite graph, health, validate, notes, queues, or task state.
- Do not edit a vault `.gitignore` unless the user explicitly asks.

## Output

- Keep text output concise and include the helper output when it is short.
- For JSON requests, return the helper's JSON without additional prose unless a failure needs explanation.
- If the helper is missing, say that the installed Ars Contexta plugin needs to be refreshed.
