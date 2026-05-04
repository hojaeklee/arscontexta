# Repository Instructions

- Use Conventional Commits for commit messages.
- After a plan has been implemented, commit the completed changes.
- For plugin-facing changes, update `plugins/hippocampusmd/.codex-plugin/plugin.json` with a SemVer version bump:
  - patch for fixes and internal cleanup that should refresh the installed plugin,
  - minor for new skills, helpers, or backwards-compatible workflow additions,
  - major for breaking manifest, skill, or workflow changes.
- When the version changes, run `scripts/check-codex-plugin.sh` and reinstall or refresh the local Codex plugin so the cache uses the new version.
