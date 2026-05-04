---
name: hippocampusmd-session
description: Use when the user asks Codex to orient at session start, validate recent note writes, or capture a session handoff in a HippocampusMD vault.
---

# HippocampusMD Session

Run explicit Codex session-rhythm workflows for `orient`, `validate`, and
`capture` requests.

## Mode Selection

- `orient`: session start, "what should I do", "where are we", resume work.
- `validate`: after writing notes, checking a note, validating changed markdown.
- `capture`: session end, handoff, save what happened, prepare next session.

Treat the current working directory as the vault unless the user gives another
path.

## Orient

Run the bounded helper when available:

```bash
plugins/hippocampusmd/scripts/session-orient.sh . --limit 25 --format text
```

From an installed plugin package, discover the helper relative to the plugin
root:

```bash
plugins/hippocampusmd/scripts/session-orient.sh . --limit 25 --format text
```

Report:

- current vault marker state
- current goals or session handoff excerpts
- inbox, queue, observation, tension, session, and health report counts
- one recommended next action

Orientation is read-only. Do not run full health scans unless the user asks.

## Validate

Run lightweight hook-equivalent validation:

```bash
plugins/hippocampusmd/scripts/session-validate.sh . --file notes/example.md --limit 25 --format text
plugins/hippocampusmd/scripts/session-validate.sh . --changed --limit 25 --format text
```

Validation is warning-only. It checks frontmatter, `description:`, `topics:`,
and obvious unresolved wiki links. Full semantic validation belongs to the
future `hippocampusmd-validate` skill.

Do not make this workflow depend on optional search tooling. If an optional wrapper exists it may
be used, but the bundled script path remains the stable fallback.

## Capture

Before writing, confirm the summary that should be saved. If the user did not
provide a summary, synthesize a concise one from the visible conversation and
state that it is not a complete transcript.

Write the summary to a temporary file, then run:

```bash
plugins/hippocampusmd/scripts/session-capture.sh . --summary-file /tmp/summary.md
```

Add `--next-file /tmp/next.md` when the handoff has a separate next-action
section. Use `--dry-run` when the user wants a preview.

Codex cannot automatically save a complete transcript unless the user provides
one or Codex exposes a stable transcript API. Capture writes a markdown handoff
to `ops/sessions/YYYYMMDD-HHMMSS.md` and updates `ops/sessions/current.md`.

## Git

Do not auto-commit as a session hook replacement. When useful, surface
`git status --short` and recommend an intentional Conventional Commit.
