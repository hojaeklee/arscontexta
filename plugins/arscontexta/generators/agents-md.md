# Ars Contexta Agent Context

This is a Codex-oriented Ars Contexta vault for {{DOMAIN}}.

## How To Work Here

- Treat markdown files as a local knowledge graph.
- Use wiki links for meaningful connections between notes.
- Keep durable knowledge in `notes/`, raw capture in `inbox/`, and operational state in `ops/`.
- Use `self/` for persistent agent identity and operating memory.
- Prefer small, traceable edits and preserve existing user notes.

## Vault Configuration

- Preset: {{PRESET}}
- Durable note type: {{NOTE_TYPE}}
- Topic map type: {{TOPIC_MAP}}
- Focus: {{FOCUS_TERM}}

## Available Codex Skills

- `arscontexta-help`: orient to this vault or the plugin.
- `arscontexta-health`: run a bounded, read-only health check.
- `arscontexta-setup`: create or complete minimal Codex vault scaffolding.
- `arscontexta-session`: orient, validate recent writes, and capture session handoffs explicitly.

## Operating Model

This Codex setup creates a usable vault with explicit session workflows, deterministic helper scripts, and no hidden background automation.

## Next Action

After setup, run `arscontexta-session orient`, then `arscontexta-health` to verify the vault.
