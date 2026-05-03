# Platform Notes

Codex is the only supported Ars Contexta platform in this repository.

The runtime plugin lives at `plugins/arscontexta/`. Platform notes here are
non-runtime guidance for how Codex workflows are expected to behave.

## Structure

```text
platforms/
|-- codex/      # Codex workflow notes
|-- shared/     # Platform-neutral feature/template notes
+-- README.md
```

Do not add platform-specific packaging here unless it is backed by an active
installable plugin and smoke tests.
