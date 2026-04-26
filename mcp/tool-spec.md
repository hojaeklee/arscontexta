# Ars Contexta MCP Tool Spec

This document defines candidate MCP tools for deterministic vault operations.
The current implementation is a CLI prototype in `scripts/mcp-vault-tools.sh`.

## Tool Boundary

Tools are either read-only or explicitly write-capable. Read-only tools may run
without confirmation. Write-capable tools must require explicit user approval in
the calling skill before they are invoked.

All tools accept a vault path and should resolve it to an absolute path in their
response. Tools should return structured JSON and should not print unbounded raw
matches.

## Candidate Tools

### `arscontexta.vault.inspect`

Read-only. Summarizes `.arscontexta`, expected directories, config files,
markdown counts, and basic session/queue state.

### `arscontexta.links.check`

Read-only. Extracts wiki links, resolves them against markdown filenames and
relative paths, and reports dangling links by bucket: primary, operational, and
noise.

Current CLI prototype:

```bash
scripts/mcp-vault-tools.sh links.check . --limit 25
```

### `arscontexta.frontmatter.validate`

Read-only. Validates frontmatter opening delimiter, non-empty `description:`,
`topics:`, and obvious unresolved wiki links for one file, changed markdown, or
all notes.

Current CLI prototype:

```bash
scripts/mcp-vault-tools.sh frontmatter.validate . --file notes/example.md --limit 25
scripts/mcp-vault-tools.sh frontmatter.validate . --changed --limit 25
scripts/mcp-vault-tools.sh frontmatter.validate . --all --limit 25
```

### `arscontexta.graph.summary`

Read-only. Reports note counts, link counts, orphan candidates, hubs, sparse
areas, and graph density. Future wrapper for graph/stat skills.

### `arscontexta.queue.read`

Read-only. Summarizes queue depth, pending tasks, blocked tasks, stale batches,
and next candidate work without mutating queue state.

### `arscontexta.note.create`

Future write-capable tool. Creates a schema-aware note only after the calling
skill has explicit approval. It must avoid overwrites and return the created
path, normalized title, and validation status.

### `arscontexta.search.bridge`

Optional future bridge to qmd or another vector-search provider. Search is an
accelerator only; Ars Contexta skills must still work with keyword search and
wiki-link traversal.

## Error Behavior

- Valid execution returns exit `0`, even when findings are `WARN` or `FAIL`.
- Usage, invalid paths, or invalid option combinations return exit `2`.
- Unexpected internal failures return exit `3`.

## Compatibility

The CLI prototype is intentionally not a production MCP server. Future MCP
servers should preserve the same tool names, read/write boundaries, and JSON
fields where practical.
