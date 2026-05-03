---
name: arscontexta-tutorial
description: Use when the user asks Codex for an Ars Contexta tutorial, onboarding walkthrough, guided first use, or help learning the vault workflow by doing.
---

# Ars Contexta Tutorial

Guide a new user through Ars Contexta with a conversational, safe-by-default walkthrough. The tutorial teaches the shape of the system before it writes anything, and turns sample note creation into an explicit opt-in moment rather than a hidden side effect.

## When Invoked

1. Treat the current directory as the vault unless the user gives another path.
2. Read runtime context when present:
   - `ops/derivation-manifest.md` for domain vocabulary such as notes folder, note name, note plural, reduce/process verb, reflect/connect verb, topic map wording, and inbox folder.
   - `ops/config.yaml` for configured notes folder, processing depth, schema hints, templates, and domain-specific quality expectations.
3. If those files are absent, use universal defaults: notes folder `notes/`, note name `note`, topic map `index`, and ordinary Ars Contexta markdown conventions.
4. Use normal Codex conversation: ask concise questions, wait for user replies, and ask for explicit confirmations before persistent writes.

## Starting, Resuming, And Resetting

- New tutorial: start with track selection and explain that the first pass is report/planning mode before writes.
- Resume: if `ops/tutorial-state.yaml` exists, read it and offer to resume from its saved track and current step. Do not re-ask for the track unless the user wants to change it.
- Persistence: write or update `ops/tutorial-state.yaml` only after the user confirms they want a persistent tutorial session.
- Completion: when all five steps are finished, mark `current_step: 6`, preserve the original start time, and add a completion timestamp.
- Reset requires explicit confirmation. Before resetting, show the current saved state and ask the user to confirm that Codex should replace or remove only `ops/tutorial-state.yaml`; never delete tutorial notes as part of reset unless the user separately names the files.

State format when persistence is approved:

```yaml
track: researcher
current_step: 1
completed_steps: []
started: "2026-05-03T12:00:00Z"
last_activity: "2026-05-03T12:00:00Z"
```

## Track Selection

Offer three tracks and let the user pick in plain language:

- researcher: papers, claims, literature notes, methods, cross-source synthesis.
- manager: meetings, decisions, projects, stakeholders, institutional memory.
- personal: daily observations, goals, reflective journaling, patterns, self-knowledge.

The track changes examples and wording, not the five-step structure.

## Tutorial Arc

Every step uses WHY / DO / SEE:

- WHY explains why the workflow matters.
- DO gives the user a small action or previews the exact action Codex would take.
- SEE shows the artifact, connection, or reasoning the user should notice.

The five steps are:

- capture: turn one complete thought into a durable note candidate.
- discover: compare a second thought with the first and link only when the relationship is genuine.
- process: extract one or two atomic insights from a short raw paragraph.
- maintain: check the sample notes for schema, descriptions, links, and orphan risks.
- reflect: review the tiny graph and choose a natural next workflow.

## Safe Write Behavior

- Stay in report/planning mode before writes by default. Preview proposed note titles, filenames, frontmatter, body text, links, and state changes before creating or editing files.
- Sample note creation requires explicit confirmation. Ask before creating the first tutorial note, before creating extracted notes, and before editing links into any note.
- Preserve existing vault content. Search for likely duplicate filenames or titles first, choose non-conflicting tutorial filenames, and do not overwrite or broadly rewrite existing notes.
- write only approved tutorial notes under the configured notes folder. Do not write sample content outside that folder.
- Label tutorial-created content clearly in frontmatter or body text, for example `tutorial: true` or a short sentence saying it was created during the Ars Contexta tutorial.
- Use valid YAML frontmatter with at least `description` and `topics`. Add local schema fields only when the vault makes them clear.
- Use wiki links where genuine. Apply the articulation test: `[[note A]] connects to [[note B]] because ...`.
- Use no forced connections. If two tutorial notes do not meaningfully connect, say so and leave them separate.
- After any sample note creation or link edit, recommend running `arscontexta-validate` on the changed notes.

## Step Guidance

### 1. capture

WHY: explain that Ars Contexta starts from complete thoughts, not vague labels. A good title should read naturally inside another sentence.

DO: ask for one sentence appropriate to the chosen track. Preview a proposed note with safe filename, `description`, `topics`, and two or three sentences of body text. Create it only after confirmation.

SEE: show how the note title works as prose inside a wiki link and explain how that makes future traversal useful.

### 2. discover

WHY: explain that knowledge compounds through meaningful relationships, not through link volume.

DO: ask for a second thought, preview a second note, and compare it with the first. If the relationship passes the articulation test, preview the exact wiki link or `relevant_notes` entry before editing.

SEE: show the connection sentence when it exists, or explain why leaving the notes unlinked keeps the graph cleaner.

### 3. process

WHY: explain that raw material becomes durable knowledge through selective extraction, not summary dumping.

DO: ask for a short paragraph from the selected track. Identify one or two atomic insights, skip low-value logistics, and preview note candidates before writing.

SEE: show the path from raw paragraph to atomic notes to possible graph connections. Mention that `arscontexta-reduce` handles this workflow at larger scale.

### 4. maintain

WHY: explain that a knowledge graph decays when descriptions are vague, links break, and notes drift away from topic maps.

DO: inspect only tutorial-created notes and any directly referenced topic maps. Report description quality, YAML validity, wiki-link resolution, topic membership, and orphan risk. Ask before fixing anything.

SEE: show a small health table and mention that `arscontexta-health` checks broader vault structure while `arscontexta-validate` checks note quality in more detail.

### 5. reflect

WHY: explain that reflection turns a few notes into a model of what the system is becoming.

DO: summarize tutorial notes, genuine links, standalone notes, and remaining gaps. Ask what workflow the user wants next.

SEE: show a compact text graph or list of connections and recommend a natural next step: `arscontexta-reduce` for source extraction, `arscontexta-reflect` for connection discovery, `arscontexta-graph` for graph structure, `arscontexta-health` for maintenance, `arscontexta-pipeline` for end-to-end source processing, or `arscontexta-learn` when that future workflow is available.

## Note Quality Expectations

Tutorial-created notes are real vault content only when the user opts in. They should still meet normal Ars Contexta quality expectations:

- prose-sentence titles when the vault convention supports them
- valid YAML frontmatter
- a useful `description` that adds scope, mechanism, or implication beyond the title
- `topics` entries that point to genuine hubs or topic maps
- wiki links where genuine, with no forced connections
- concise body text that remains useful without the tutorial transcript open

## Boundaries

- Do not assume special UI prompts or named tool forms. Use ordinary Codex conversation and explicit user replies.
- Do not require deterministic helper scripts; this is a conversational educational workflow.
- Do not mutate `ops/queue/*`, `ops/observations/`, `ops/tensions/`, or non-tutorial notes unless the user separately asks for that work.
- Do not create a persistent tutorial session unless the user confirms persistence.
- Do not overwrite notes, delete existing vault content, or hide file writes inside explanatory text.
