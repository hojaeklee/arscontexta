# Optional MCP Layer

Ars Contexta treats MCP as an optional deterministic layer, not as the core
methodology. The vault must remain useful through Codex skills, shell helpers,
`rg`, and wiki-link traversal even when no MCP server is installed.

## Boundary

Good MCP candidates are operations with clear inputs, clear outputs, and no
methodology judgment:

- vault graph and link checks
- YAML/frontmatter validation
- vault indexing and inventory
- queue reads and summaries
- schema-aware note creation with explicit approval
- optional qmd/vector-search bridging

MCP should not own:

- setup and derivation conversations
- recommendation or architecture judgment
- note interpretation and synthesis
- broad rewrites or refactors
- hidden background automation

## Fallback Rule

Every Codex skill must work without MCP. The preferred fallback order is:

1. MCP tool when a compatible server is available.
2. Bundled deterministic script from `scripts/` or `plugins/arscontexta/scripts/`.
3. Local `rg`, `find`, and shell inspection.

The first prototype is a command-line contract, not a registered MCP server:

```bash
scripts/mcp-vault-tools.sh links.check . --limit 25
scripts/mcp-vault-tools.sh frontmatter.validate . --file notes/example.md --limit 25
```

This lets later MCP server work wrap stable behavior without making current
Codex skills depend on MCP.
