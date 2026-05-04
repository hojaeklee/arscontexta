# HippocampusMD Agent Context

This is a Codex-oriented HippocampusMD vault for {{DOMAIN}}.

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

- `hippocampusmd-help`: orient to this vault or the plugin.
- `hippocampusmd-health`: run a bounded, read-only health check.
- `hippocampusmd-setup`: create or complete minimal Codex vault scaffolding.
- `hippocampusmd-session`: orient, validate recent writes, and capture session handoffs explicitly.

## Operating Model

This Codex setup creates a usable vault with explicit session workflows, deterministic helper scripts, and no hidden background automation.

## Next Action

After setup, run `hippocampusmd-session orient`, then `hippocampusmd-health` to verify the vault.
