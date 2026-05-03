---
name: arscontexta-learn
description: Use when the user asks Codex to research a topic, capture research into an Ars Contexta vault, or grow the knowledge graph from web results, local files, or provided source material.
---

# Ars Contexta Learn

Plan and capture research with provenance so the result can enter the Ars Contexta processing pipeline. Learn is an intake workflow: it gathers or organizes source material, writes an approved research capture into the inbox, and hands off to existing queue/pipeline skills.

## When Invoked

1. Treat the current directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/config.yaml` for research defaults, pipeline chaining language, configured paths, and domain settings.
   - `ops/derivation-manifest.md` for vocabulary such as inbox folder, note names, domain name, hub/topic map names, and processing skill names.
3. Use defaults when config is absent: inbox folder `inbox/`, source type names from this skill, and chaining mode `suggested`.
4. Use normal Codex conversation. Present the research plan, ask for confirmation before network use or file writes, and keep source boundaries visible.

## Topic Selection

- If the user provides a topic, draft a brief research plan for that topic before gathering or writing anything.
- If no topic is provided, inspect `self/goals.md` for a high-priority unexplored direction and suggest one topic. If no usable goal exists, ask what the user wants to research.
- If the user provides local files or pasted source material, treat that as the offline path and build the capture from those sources unless they explicitly ask for web research too.
- If the topic is too broad, propose a narrower research question and ask for confirmation before continuing.

## Research Modes

Web/network research is optional. Require explicit confirmation before web/network research, even when the user says "research", because network use changes cost, time, and source provenance.

Supported modes:

- offline path: use user-provided research text, local files, or existing inbox/source material.
- web results: use available Codex web research only after confirmation and cite every source used.
- mixed: combine local material with confirmed web results while keeping sections and provenance distinct.

Do not assume a specific web provider. If a research connector, browser, or web search tool is unavailable or not approved, continue with the offline path or ask the user for source material.

## Capture Workflow

1. Read target config and vocabulary.
2. Identify the topic or proposed topic from `self/goals.md`.
3. Show a plan with research question, intended mode, expected source boundaries, and whether any file write is planned.
4. If web/network research is needed, ask for explicit confirmation before web/network research.
5. Gather source material from approved web results, local files, or user-provided material.
6. Draft a research capture preview with frontmatter, filename, findings, sources, and follow-up directions.
7. Create research capture files only after confirmation.
8. Write only under the configured inbox folder.
9. Preserve existing vault content by checking for filename collisions and choosing a non-overwriting filename when needed.
10. Report the created file and recommend `arscontexta-seed` or `arscontexta-pipeline` for processing.

No deterministic helper script is needed for this first port; the workflow depends on confirmation, optional network access, and source provenance.

## Research Capture Format

Use valid YAML frontmatter. Include:

```yaml
---
description: "One or two sentences summarizing the captured research."
source_type: "web-results"
research_prompt: "The exact research question or prompt Codex used."
generated: "2026-05-03T12:00:00Z"
domain: "Domain name when known"
topics: ["[[index]]"]
---
```

Allowed `source_type` values:

- `web-results`
- `local-files`
- `user-provided-material`
- `mixed-sources`

Omit `domain` only when no domain is known. Keep `topics` genuine; use a configured hub/topic map when clear, otherwise use the safest local default.

Use this body structure:

```markdown
# Topic Title

## Key Findings

- Finding stated as a clear proposition, with source attribution where relevant.

## Sources

- Source title or local path - URL or location, plus a short note about what it contributed.

## Research Directions

- Follow-up question or unexplored angle discovered during the research.
```

## Source Boundaries

Clear source boundaries are mandatory:

- web results: cite title and URL for every web source used.
- local file excerpts: include local paths and avoid implying those files are external evidence.
- user-provided material: label it as user-provided material rather than independently verified research.
- synthesized findings: distinguish Codex synthesis from direct source claims.

No fabricated sources or URLs. If a source cannot be verified or named, label it as unavailable and avoid presenting it as a citation.

## Pipeline Handoff

Do not process research directly. Learn creates source material for the pipeline; it does not extract notes, weave links, reweave old notes, verify claims, or run queue workers.

After a confirmed inbox write, recommend one next step:

- `arscontexta-seed` for preparing the capture as a queued source.
- `arscontexta-pipeline` for planning visible end-to-end source processing.

Respect configured chaining language from `ops/config.yaml`, but Do not start downstream processing automatically. If config says automatic chaining, explain that this Codex port still requires visible user confirmation before running downstream work.

## Goals Updates

If `self/goals.md` exists and the research reveals genuine new directions, preview any proposed update before writing. Do not add filler goals, and do not update goals when the user only wanted a one-off capture.

## Boundaries

- Use Codex conversation and explicit user replies.
- Use explicit Codex research modes and do not hide background research.
- Do not mutate `ops/queue/*`; hand off to `arscontexta-seed` or `arscontexta-pipeline`.
- Do not write outside the configured inbox folder unless the user separately asks for a different destination.
- Do not overwrite existing research captures, notes, goals, or queue files.
