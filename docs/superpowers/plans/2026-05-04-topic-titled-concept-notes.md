# Topic-Titled Concept Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make topic-titled concept notes first-class alongside prose-titled research claims for mixed research-learning HippocampusMD vaults.

**Architecture:** Add a reusable concept-note capability rather than a separate learning preset in this first pass. The research preset will generate a concept-note template and concept extraction guidance, while core methodology, validation, indexing, and skill docs define `type: concept` as the explicit exception to prose-as-title rules.

**Tech Stack:** Markdown methodology/reference files, Bash setup helper, Python VaultIndex, shell test scripts under `scripts/tests/`, Codex plugin manifest SemVer.

---

## Issue Context

Source issue: [hojaeklee/hippocampusmd#53](https://github.com/hojaeklee/hippocampusmd/issues/53)

Decision already made by the user:

- Topic-titled concept notes are allowed as an explicit exception to prose-as-title.
- The exception is guarded by `type: concept`.
- Concept notes should work in a shared research-learning graph, not only in a future pure-learning preset.

Design choice for this implementation:

- Do not add a new preset yet.
- Add a general concept-note capability and enable it in the research preset.
- Keep generated concept notes in `notes/` by default.
- Make the VaultIndex/CSV export sufficient for Obsidian Bases without making Bases a dependency.

## File Structure

- Modify `plugins/hippocampusmd/reference/templates/learning-note.md`
  - Retire the vague learning-note shape in favor of a concept-note reference template.
- Create `plugins/hippocampusmd/reference/templates/concept-note.md`
  - Canonical reference template for topic-titled concept notes.
- Modify `plugins/hippocampusmd/reference/templates/base-note.md`
  - Mention `concept` as a special type, but point to the concept template for its title exception.
- Modify `plugins/hippocampusmd/generators/features/atomic-notes.md`
  - Document the `type: concept` exception to prose-as-title.
- Modify `plugins/hippocampusmd/generators/features/schema.md`
  - Add `concept` to enum guidance and explain when `type: concept` matters for query.
- Modify `plugins/hippocampusmd/generators/features/templates.md`
  - Document concept-note templates as an accepted multi-note-type template.
- Modify `plugins/hippocampusmd/generators/features/processing-pipeline.md`
  - Teach reduce/connect/verify when to extract concept notes versus claim notes.
- Modify `plugins/hippocampusmd/generators/features/mocs.md`
  - Explain how topic maps can contain both concept notes and claim notes.
- Modify `plugins/hippocampusmd/reference/components.md`
  - Add concept notes as a component under Notes/Templates.
- Modify `plugins/hippocampusmd/reference/vocabulary-transforms.md`
  - Keep Learning folder mapping, but clarify mixed research-learning uses `notes/`.
- Modify `plugins/hippocampusmd/reference/use-case-presets.md`
  - Clarify that research can include concept notes for durable domain primitives.
- Modify `plugins/hippocampusmd/reference/tradition-presets.md`
  - Add mixed research-learning guidance without creating a preset.
- Modify `plugins/hippocampusmd/methodology/note-design.md`
  - Add a Core Idea entry for concept notes.
- Create `plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md`
  - Durable methodology claim explaining the exception and its guardrails.
- Modify `plugins/hippocampusmd/presets/research/categories.yaml`
  - Add `concepts` as an extraction category.
- Modify `plugins/hippocampusmd/presets/research/preset.yaml`
  - Add starter/config metadata for concept notes.
- Modify `plugins/hippocampusmd/scripts/setup-vault.sh`
  - Generate `templates/concept-note.md` for research vaults.
  - Add concept-note guidance to generated `manual/getting-started.md`.
  - Preserve idempotency: do not overwrite existing templates.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-reduce/SKILL.md`
  - Require extraction reports to distinguish concept note candidates from claim note candidates.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-learn/SKILL.md`
  - Mention that learn creates source captures and downstream reduce may produce concept notes.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-reflect/SKILL.md`
  - Explain how concept notes serve as prerequisites, hubs, and bridge nodes.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-validate/SKILL.md`
  - Mention `type: concept` title exception and template-aware validation.
- Modify `plugins/hippocampusmd/skills/hippocampusmd-index/SKILL.md`
  - Document concept discovery via VaultIndex CSV/JSON and `note_type`.
- Modify `plugins/hippocampusmd/scripts/vault_index.py`
  - Add `concepts` count to summary metrics.
  - Add `vault-index-concepts.csv` export with concept-specific fields.
- Modify `scripts/tests/test-setup-vault.sh`
  - Assert research setup creates concept template and category.
- Modify `scripts/tests/test-vault-index.sh`
  - Assert concepts are counted and exported.
- Modify skill/doc tests:
  - `scripts/tests/test-reduce-skill.sh`
  - `scripts/tests/test-learn-skill.sh`
  - `scripts/tests/test-reflect-skill.sh`
  - `scripts/tests/test-validate-skill.sh`
  - `scripts/tests/test-index-skill.sh`
- Modify `scripts/check-codex-plugin.sh`
  - Check the new reference template and methodology note exist.
- Modify `plugins/hippocampusmd/.codex-plugin/plugin.json`
  - Patch version bump, because this changes plugin-facing instructions and generated setup assets.

## Concept Note Contract

Concept notes are for learnable entities, mechanisms, theories, methods, structures, terms of art, anatomical structures, and prerequisite concepts.

They may be titled as topics:

```markdown
# hippocampus
```

They must declare `type: concept`:

```yaml
---
description: Medial temporal lobe structure central to episodic memory formation and spatial context binding
type: concept
domain: neuroscience
mastery: new | developing | solid | expert
prerequisites: ["[[medial temporal lobe]]"]
enables: ["[[episodic memory]]", "[[spatial navigation]]"]
retrieval_questions:
  - "What memory functions depend on the hippocampus?"
aliases: ["hippocampal formation"]
topics: ["[[memory systems]]", "[[neuroanatomy]]"]
created: YYYY-MM-DD
---
```

The title exception does not apply to standard claim/insight/fact notes. Claims still use prose-as-title:

```markdown
# hippocampal lesions impair new episodic memory formation more than remote semantic recall
```

Topic maps/MOCs still use `type: moc` and organize notes. They are not concept notes.

## Task 1: Add Concept Note Reference Template And Methodology

**Files:**
- Create: `plugins/hippocampusmd/reference/templates/concept-note.md`
- Modify: `plugins/hippocampusmd/reference/templates/learning-note.md`
- Modify: `plugins/hippocampusmd/reference/templates/base-note.md`
- Create: `plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md`
- Modify: `plugins/hippocampusmd/methodology/note-design.md`

- [ ] **Step 1: Write the new concept-note reference template**

Create `plugins/hippocampusmd/reference/templates/concept-note.md`:

```markdown
---
description: One sentence explaining the concept's scope, mechanism, or learning value
type: concept
domain: subject area
mastery: new | developing | solid | expert
prerequisites: ["[[prerequisite concept]]"]
enables: ["[[downstream concept]]"]
retrieval_questions:
  - "Question that tests understanding of this concept"
aliases: []
created: YYYY-MM-DD
---

# topic-title naming the concept

One-paragraph definition in the user's own words. Explain what this concept is, why it matters, and how it connects to nearby claims.

## Key Facts

- Fact worth remembering, preferably linked to supporting claim notes when available.

## Prerequisites

- [[prerequisite concept]] -- why this must be understood first

## Enables

- [[downstream concept]] -- what this concept makes understandable

## Retrieval Questions

- Question that tests understanding of the concept.

---

Relevant Notes:
- [[related claim note]] -- relationship context

Topics:
- [[topic-map]]
```

- [ ] **Step 2: Reframe the learning-note template as an alias to concept notes**

Replace `plugins/hippocampusmd/reference/templates/learning-note.md` with:

```markdown
---
description: Learning-domain concept note template; topic-titled notes are valid only when type is concept
type: concept
domain: subject area
mastery: new | developing | solid | expert
prerequisites: ["[[prerequisite concept]]"]
enables: ["[[downstream concept]]"]
retrieval_questions:
  - "Question that tests understanding of this concept"
aliases: []
created: YYYY-MM-DD
---

# topic-title naming the concept

One-paragraph definition in the learner's own words. Explain what this concept is, why it matters, and how it connects.

## Key Facts

- Fact worth remembering.

## Prerequisites

- [[prerequisite concept]] -- why this must be understood first

## Enables

- [[downstream concept]] -- what this concept makes understandable

## Retrieval Questions

- Question that tests understanding of the concept.

---

Topics:
- [[study-area]]
```

- [ ] **Step 3: Update the base note template enum**

In `plugins/hippocampusmd/reference/templates/base-note.md`, change:

```yaml
type: insight | pattern | preference | fact | decision | question
```

to:

```yaml
type: insight | pattern | preference | fact | decision | question | concept
```

Add this note below the body guidance:

```markdown
Use `type: concept` only for learnable entities or domain primitives. Concept notes may use topic titles and should follow `reference/templates/concept-note.md`; ordinary insight, fact, and claim notes still use prose-as-title.
```

- [ ] **Step 4: Add the methodology claim**

Create `plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md`:

```markdown
---
description: Concept notes are a guarded exception to prose-as-title because learnable entities need stable topic handles while claims need sentence-form APIs
kind: research
topics: ["[[note-design]]", "[[discovery-retrieval]]"]
---

# topic-titled concept notes are valid when the note models a learnable entity

Prose-as-title remains the default for claims because claim titles function as callable arguments. But a mixed research-learning vault also needs stable handles for learnable entities: structures, mechanisms, theories, methods, terms of art, and prerequisite concepts. A note titled `hippocampus` can be correct when the note's job is to model the concept itself rather than assert one claim about it.

The guardrail is `type: concept`. Topic-titled notes are valid only when the frontmatter declares `type: concept` and the body provides a definition, prerequisites, downstream concepts, and retrieval questions. Without that guardrail, topic labels degrade the graph by hiding what the note argues. With it, concept notes become durable learning objects that claim notes can depend on.

This creates a productive division of labor. Concept notes answer "what is this and how do I learn it?" Claim notes answer "what is true, contested, or useful about this?" Topic maps answer "what do we know in this area and where should I start?" The three forms coexist in one graph because `type` separates their roles while wiki links preserve traversal across them.

---

Relevant Notes:
- [[title as claim enables traversal as reasoning]] -- default rule: claim notes should keep prose-as-title because their titles compose as arguments
- [[student learning uses prerequisite graphs with spaced retrieval]] -- domain example: concept notes carry prerequisites, mastery, and retrieval questions
- [[type field enables structured queries without folder hierarchies]] -- retrieval guardrail: `type: concept` lets concept notes coexist with claims in `notes/`
- [[faceted classification treats notes as multi-dimensional objects rather than folder contents]] -- theoretical basis: concept-ness is a note property, not necessarily a folder

Topics:
- [[note-design]]
- [[discovery-retrieval]]
```

- [ ] **Step 5: Add the concept note to the note-design MOC**

In `plugins/hippocampusmd/methodology/note-design.md`, under `## Core Ideas` and `### Research`, add:

```markdown
- [[topic-titled concept notes are valid when the note models a learnable entity]] -- Guarded exception to prose-as-title: concept notes use topic handles when they model learnable entities, while claim notes remain sentence-form arguments
```

- [ ] **Step 6: Run focused file checks**

Run:

```bash
test -f "plugins/hippocampusmd/reference/templates/concept-note.md"
test -f "plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md"
rg -n "type: concept|topic-titled concept notes" plugins/hippocampusmd/reference/templates plugins/hippocampusmd/methodology/note-design.md
```

Expected: both `test` commands exit 0 and `rg` prints the new concept-template and MOC references.

- [ ] **Step 7: Commit**

```bash
git add plugins/hippocampusmd/reference/templates/concept-note.md plugins/hippocampusmd/reference/templates/learning-note.md plugins/hippocampusmd/reference/templates/base-note.md "plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md" plugins/hippocampusmd/methodology/note-design.md
git commit -m "docs: define concept note title exception"
```

## Task 2: Update Generated Methodology Feature Guidance

**Files:**
- Modify: `plugins/hippocampusmd/generators/features/atomic-notes.md`
- Modify: `plugins/hippocampusmd/generators/features/schema.md`
- Modify: `plugins/hippocampusmd/generators/features/templates.md`
- Modify: `plugins/hippocampusmd/generators/features/mocs.md`
- Modify: `plugins/hippocampusmd/generators/features/processing-pipeline.md`
- Modify: `plugins/hippocampusmd/reference/components.md`
- Modify: `plugins/hippocampusmd/reference/vocabulary-transforms.md`
- Modify: `plugins/hippocampusmd/reference/use-case-presets.md`
- Modify: `plugins/hippocampusmd/reference/tradition-presets.md`

- [ ] **Step 1: Document the atomic-notes exception**

In `plugins/hippocampusmd/generators/features/atomic-notes.md`, after the "Bad titles" examples, add:

```markdown
### Explicit Exception: Concept Notes

Concept notes are the only built-in exception to prose-as-title. Use a topic title when all of these are true:

- The note declares `type: concept`.
- The title names a learnable entity, mechanism, theory, method, anatomical structure, term of art, or prerequisite concept.
- The body defines the concept and includes learning scaffolding such as prerequisites, downstream concepts, or retrieval questions.

Examples:
- `hippocampus` with `type: concept` is valid when the note defines the structure and links prerequisites and downstream memory claims.
- `basal ganglia` with `type: concept` is valid when the note models the learnable system.
- `hippocampus supports episodic memory formation` should be a claim note, not a concept note.

Do not use this exception for vague topic buckets. If the note is a map of other notes, use `type: moc`. If the note argues something, use prose-as-title.
```

- [ ] **Step 2: Add `concept` to schema guidance**

In `plugins/hippocampusmd/generators/features/schema.md`, update both default enum lists:

```yaml
type: insight | pattern | preference | fact | decision | question | concept
```

and:

```yaml
type: [insight, pattern, preference, fact, decision, question, concept]
```

Add this enum row:

```markdown
| `concept` | A learnable entity or domain primitive; may use a topic title only when the note follows concept-note structure |
```

- [ ] **Step 3: Add concept-note template guidance**

In `plugins/hippocampusmd/generators/features/templates.md`, after "When to Create New Templates", add:

```markdown
### Concept Note Template

Mixed research-learning vaults should keep a concept-note template available from setup rather than waiting for three manual examples. Concept notes are a known cross-domain shape: they need `type: concept`, a topic title, prerequisites, downstream concepts, and retrieval questions. This is not speculative ceremony; it is the schema that protects the prose-as-title exception from becoming generic topic buckets.
```

- [ ] **Step 4: Add mixed topic-map guidance**

In `plugins/hippocampusmd/generators/features/mocs.md`, after the topic map structure example, add:

```markdown
Concept notes and claim notes can appear in the same {DOMAIN:topic map}. Use the context phrase to make the role clear:

```markdown
- [[hippocampus]] -- concept: start here for definition, prerequisites, and retrieval questions
- [[hippocampal lesions impair new episodic memory formation more than remote semantic recall]] -- claim: evidence about memory function
```

Concept notes orient learning; claim notes carry arguments. A {DOMAIN:topic map} should not duplicate the concept note's definition or the claim note's reasoning.
```

- [ ] **Step 5: Add reduce/connect guidance to processing pipeline**

In `plugins/hippocampusmd/generators/features/processing-pipeline.md`, in the extraction guidance section, add:

```markdown
**Concept extraction:** When a source introduces durable vocabulary, anatomy, mechanisms, methods, theories, or prerequisite concepts, propose `type: concept` notes separately from claim notes. A concept note should define the learnable object and link prerequisites/downstream concepts. A claim note should assert something specific about that object.

Use this distinction:

| Source material | Note shape |
|----------------|------------|
| "The hippocampus is part of the medial temporal lobe..." | `hippocampus` concept note |
| "Hippocampal lesions impair new episodic memory formation..." | prose-titled claim note |
| "Open question: whether adult hippocampal neurogenesis affects human memory..." | question/tension note |
```

- [ ] **Step 6: Update reference docs**

Apply these targeted additions:

In `plugins/hippocampusmd/reference/components.md`, under "Notes -- Atomic Knowledge Units", add:

```markdown
**Concept notes:** Concept notes are typed knowledge units for learnable entities. They use `type: concept`, may use topic titles, and carry prerequisites/retrieval questions. They live in the same graph as claims unless a domain-specific vault maps the notes folder to `concepts/`.
```

In `plugins/hippocampusmd/reference/vocabulary-transforms.md`, below the folder mapping table, add:

```markdown
Mixed research-learning vaults should usually keep `notes/` as the shared graph and distinguish concept notes with `type: concept`. A pure learning vault may still map the collection folder to `concepts/`.
```

In `plugins/hippocampusmd/reference/use-case-presets.md`, under Research "Key settings", add:

```markdown
- `concept_notes: true` (research sources often introduce durable vocabulary and methods that claims depend on)
```

In `plugins/hippocampusmd/reference/tradition-presets.md`, under Learning derivation, add:

```markdown
Mixed research-learning vaults should combine Research claim extraction with Learning concept-note scaffolding rather than choosing one preset exclusively.
```

- [ ] **Step 7: Run focused documentation checks**

Run:

```bash
rg -n "Concept notes|type: concept|concept extraction|concept_notes" plugins/hippocampusmd/generators/features plugins/hippocampusmd/reference
```

Expected: output includes `atomic-notes.md`, `schema.md`, `templates.md`, `mocs.md`, `processing-pipeline.md`, `components.md`, `vocabulary-transforms.md`, `use-case-presets.md`, and `tradition-presets.md`.

- [ ] **Step 8: Commit**

```bash
git add plugins/hippocampusmd/generators/features/atomic-notes.md plugins/hippocampusmd/generators/features/schema.md plugins/hippocampusmd/generators/features/templates.md plugins/hippocampusmd/generators/features/mocs.md plugins/hippocampusmd/generators/features/processing-pipeline.md plugins/hippocampusmd/reference/components.md plugins/hippocampusmd/reference/vocabulary-transforms.md plugins/hippocampusmd/reference/use-case-presets.md plugins/hippocampusmd/reference/tradition-presets.md
git commit -m "docs: add concept note generation guidance"
```

## Task 3: Generate Concept Template In Research Vault Setup

**Files:**
- Modify: `plugins/hippocampusmd/presets/research/categories.yaml`
- Modify: `plugins/hippocampusmd/presets/research/preset.yaml`
- Modify: `plugins/hippocampusmd/scripts/setup-vault.sh`
- Modify: `scripts/tests/test-setup-vault.sh`

- [ ] **Step 1: Write failing setup test expectations**

In `scripts/tests/test-setup-vault.sh`, after:

```bash
assert_file "$tmp_dir/research-vault/notes/open-questions.md"
```

add:

```bash
assert_file "$tmp_dir/research-vault/templates/concept-note.md"
assert_contains "$tmp_dir/research-vault/templates/concept-note.md" "type: concept"
assert_contains "$tmp_dir/research-vault/templates/concept-note.md" "# topic-title naming the concept"
assert_contains "$tmp_dir/research-vault/templates/concept-note.md" "retrieval_questions:"
assert_contains "$tmp_dir/research-vault/ops/config.yaml" "  - concepts"
assert_contains "$tmp_dir/research-vault/ops/config.yaml" "concept_notes: true"
assert_contains "$tmp_dir/research-vault/manual/getting-started.md" "Use concept notes for durable vocabulary"
```

Add a negative assertion for personal vaults after the personal-vault assertions:

```bash
[[ ! -f "$tmp_dir/personal-vault/templates/concept-note.md" ]] || fail "personal preset should not create concept-note template by default"
```

- [ ] **Step 2: Run setup test to verify it fails**

Run:

```bash
scripts/tests/test-setup-vault.sh
```

Expected: FAIL because `templates/concept-note.md` is missing from the generated research vault.

- [ ] **Step 3: Add research extraction category**

In `plugins/hippocampusmd/presets/research/categories.yaml`, change:

```yaml
extraction_categories:
  - claims
  - evidence
  - methodology-comparisons
  - contradictions
  - open-questions
  - design-patterns
  - design-dimensions
```

to:

```yaml
extraction_categories:
  - claims
  - concepts
  - evidence
  - methodology-comparisons
  - contradictions
  - open-questions
  - design-patterns
  - design-dimensions
```

- [ ] **Step 4: Add preset metadata**

In `plugins/hippocampusmd/presets/research/preset.yaml`, under `processing_depth`, add:

```yaml
concept_notes: true
```

Under `codex_setup`, add:

```yaml
  concept_template: true
```

- [ ] **Step 5: Teach setup-vault to read the metadata**

In `plugins/hippocampusmd/scripts/setup-vault.sh`, after:

```bash
focus_term="$(yaml_scalar "$preset_file" "focus_term" "knowledge")"
```

add:

```bash
concept_notes="$(yaml_scalar "$preset_file" "concept_notes" "false")"
```

This uses the existing `yaml_scalar` helper and the already-defined `$preset_file`.

- [ ] **Step 6: Write concept metadata into generated config**

In the `ops/config.yaml)` case of `setup-vault.sh`, after the extraction category block and before `scan:`, add:

```bash
        if [[ "$concept_notes" == "true" ]]; then
          printf '%s\n' \
            "concept_notes: true" \
            "concept_template: templates/concept-note.md"
        else
          printf 'concept_notes: false\n'
        fi
```

- [ ] **Step 7: Generate the concept-note template conditionally**

Add `templates/concept-note.md` to the static file creation list before `templates/base-note.md`:

```bash
  templates/concept-note.md \
  templates/base-note.md \
```

Then add this `case` arm before `templates/base-note.md)` in `write_file()`:

```bash
    templates/concept-note.md)
      if [[ "$concept_notes" != "true" ]]; then
        return 0
      fi
      printf '%s\n' \
        "---" \
        "description: One sentence explaining the concept's scope, mechanism, or learning value" \
        "type: concept" \
        "domain: $domain" \
        "mastery: new | developing | solid | expert" \
        "prerequisites: []" \
        "enables: []" \
        "retrieval_questions:" \
        "  - \"Question that tests understanding of this concept\"" \
        "aliases: []" \
        "created: YYYY-MM-DD" \
        "---" \
        "" \
        "# topic-title naming the concept" \
        "" \
        "Define the concept in your own words. Explain why it matters, what must be understood first, and what it helps explain." \
        "" \
        "## Key Facts" \
        "" \
        "- Fact worth remembering, with links to supporting claim notes when available." \
        "" \
        "## Prerequisites" \
        "" \
        "- [[prerequisite concept]] -- why this must be understood first" \
        "" \
        "## Enables" \
        "" \
        "- [[downstream concept]] -- what this concept makes understandable" \
        "" \
        "## Retrieval Questions" \
        "" \
        "- Question that tests understanding of the concept." \
        "" \
        "---" \
        "" \
        "Relevant Notes:" \
        "- [[related claim note]] -- relationship context" \
        "" \
        "Topics:" \
        "- [[index]]" \
        > "$path"
      ;;
```

- [ ] **Step 8: Update generated getting-started guidance**

In the `manual/getting-started.md)` case, include this line only when `concept_notes` is true:

```bash
"Use concept notes for durable vocabulary, mechanisms, methods, structures, and prerequisite ideas. Concept notes declare \`type: concept\` and may use topic titles; claim notes still use prose-as-title."
```

- [ ] **Step 9: Run setup test to verify it passes**

Run:

```bash
scripts/tests/test-setup-vault.sh
```

Expected: PASS with `PASS: setup vault fixtures`.

- [ ] **Step 10: Commit**

```bash
git add plugins/hippocampusmd/presets/research/categories.yaml plugins/hippocampusmd/presets/research/preset.yaml plugins/hippocampusmd/scripts/setup-vault.sh scripts/tests/test-setup-vault.sh
git commit -m "feat: generate concept templates for research vaults"
```

## Task 4: Teach Skills To Propose And Use Concept Notes

**Files:**
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-reduce/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-learn/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-reflect/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-validate/SKILL.md`
- Modify: `plugins/hippocampusmd/skills/hippocampusmd-index/SKILL.md`
- Modify: `scripts/tests/test-reduce-skill.sh`
- Modify: `scripts/tests/test-learn-skill.sh`
- Modify: `scripts/tests/test-reflect-skill.sh`
- Modify: `scripts/tests/test-validate-skill.sh`
- Modify: `scripts/tests/test-index-skill.sh`

- [ ] **Step 1: Add failing reduce skill assertions**

In `scripts/tests/test-reduce-skill.sh`, add:

```bash
assert_contains "$SKILL" "concept note candidates"
assert_contains "$SKILL" "durable vocabulary, anatomy, mechanisms, methods, theories, or prerequisite concepts"
assert_contains "$SKILL" "type: concept"
assert_contains "$SKILL" "Topic-titled concept notes are allowed only for concept notes"
```

- [ ] **Step 2: Add failing skill assertions for learn, reflect, validate, and index**

In `scripts/tests/test-learn-skill.sh`, add:

```bash
assert_contains "$SKILL" "downstream reduce may extract concept notes"
assert_contains "$SKILL" "durable vocabulary or prerequisite concepts"
```

In `scripts/tests/test-reflect-skill.sh`, add:

```bash
assert_contains "$SKILL" "concept notes can serve as prerequisites, hubs, or bridge nodes"
assert_contains "$SKILL" "claim notes assert; concept notes define"
```

In `scripts/tests/test-validate-skill.sh`, add:

```bash
assert_contains "$SKILL" "type: concept"
assert_contains "$SKILL" "topic-titled concept notes"
```

In `scripts/tests/test-index-skill.sh`, add:

```bash
assert_contains "$SKILL" "type: concept"
assert_contains "$SKILL" "vault-index-concepts.csv"
assert_contains "$SKILL" "Obsidian Bases"
```

- [ ] **Step 3: Run skill tests to verify they fail**

Run:

```bash
scripts/tests/test-reduce-skill.sh
scripts/tests/test-learn-skill.sh
scripts/tests/test-reflect-skill.sh
scripts/tests/test-validate-skill.sh
scripts/tests/test-index-skill.sh
```

Expected: at least the new assertions fail before documentation updates.

- [ ] **Step 4: Update reduce skill**

In `plugins/hippocampusmd/skills/hippocampusmd-reduce/SKILL.md`, add under "Extraction Workflow":

```markdown
- Separate concept note candidates from claim note candidates when the source supports both. Propose concept notes for durable vocabulary, anatomy, mechanisms, methods, theories, or prerequisite concepts. Propose claim notes for specific assertions about those concepts.
- Topic-titled concept notes are allowed only for concept notes with `type: concept`. Do not use topic titles for ordinary claim, insight, fact, or question notes.
```

In "Note Writing", add:

```markdown
- When writing a concept note, use the local concept-note template when present. The title may be a topic title, but the frontmatter must include `type: concept`, `description`, and `topics`.
```

- [ ] **Step 5: Update learn skill**

In `plugins/hippocampusmd/skills/hippocampusmd-learn/SKILL.md`, add under "Pipeline Handoff":

```markdown
For mixed research-learning vaults, downstream reduce may extract concept notes from the capture when sources introduce durable vocabulary or prerequisite concepts. Learn still writes only source captures; it does not directly create concept notes unless the user separately asks for note writing.
```

- [ ] **Step 6: Update reflect skill**

In `plugins/hippocampusmd/skills/hippocampusmd-reflect/SKILL.md`, add under its connection guidance:

```markdown
- In mixed research-learning vaults, concept notes can serve as prerequisites, hubs, or bridge nodes. Claim notes assert; concept notes define. When adding links, preserve that distinction in the relationship context.
```

- [ ] **Step 7: Update validate skill**

In `plugins/hippocampusmd/skills/hippocampusmd-validate/SKILL.md`, add:

```markdown
Validation should allow topic-titled concept notes when the note declares `type: concept` and follows the local concept-note template. Topic-titled non-concept notes remain methodology warnings when local instructions require prose-as-title.
```

- [ ] **Step 8: Update index skill**

In `plugins/hippocampusmd/skills/hippocampusmd-index/SKILL.md`, add:

```markdown
Concept discovery: use `type: concept` in VaultIndex exports. `export --format csv` writes `vault-index-notes.csv` with `note_type`, and this concept-note support adds `vault-index-concepts.csv` for Obsidian Bases or spreadsheet workflows. Obsidian Bases is optional; VaultIndex remains the source of the exported metadata.
```

- [ ] **Step 9: Run skill tests to verify they pass**

Run:

```bash
scripts/tests/test-reduce-skill.sh
scripts/tests/test-learn-skill.sh
scripts/tests/test-reflect-skill.sh
scripts/tests/test-validate-skill.sh
scripts/tests/test-index-skill.sh
```

Expected: each prints its existing `PASS:` line.

- [ ] **Step 10: Commit**

```bash
git add plugins/hippocampusmd/skills/hippocampusmd-reduce/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-learn/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-reflect/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-validate/SKILL.md plugins/hippocampusmd/skills/hippocampusmd-index/SKILL.md scripts/tests/test-reduce-skill.sh scripts/tests/test-learn-skill.sh scripts/tests/test-reflect-skill.sh scripts/tests/test-validate-skill.sh scripts/tests/test-index-skill.sh
git commit -m "docs: teach skills concept note workflow"
```

## Task 5: Add Concept Discovery To VaultIndex

**Files:**
- Modify: `plugins/hippocampusmd/scripts/vault_index.py`
- Modify: `scripts/tests/test-vault-index.sh`

- [ ] **Step 1: Write failing VaultIndex test**

In `scripts/tests/test-vault-index.sh`, after the two duplicate notes are created, add a concept note:

```bash
cat > "$vault/notes/hippocampus.md" <<'EOF'
---
description: Medial temporal lobe structure central to episodic memory and spatial context binding
type: concept
domain: neuroscience
mastery: developing
prerequisites: ["[[medial temporal lobe]]"]
enables: ["[[episodic memory]]"]
retrieval_questions:
  - "What memory functions depend on the hippocampus?"
aliases: ["hippocampal formation"]
topics: ["[[index]]"]
created: 2026-05-04
---

# hippocampus

The hippocampus is a learnable concept node for memory-system research.
EOF
```

Update expected counts:

```bash
assert_contains "$first_output" "scanned: 4"
assert_contains "$second_output" "skipped: 4"
assert_contains "$status_json" '"indexed_notes": 4'
```

Add summary/export expectations:

```bash
assert_contains "$status_json" '"concepts": 1'
assert_contains "$export_json" '"note_type": "concept"'
assert_contains "$export_all" "ops/cache/exports/vault-index-concepts.csv"
assert_file "$exports_dir/vault-index-concepts.csv"

concepts_csv="$(cat "$exports_dir/vault-index-concepts.csv")"
assert_contains "$concepts_csv" "path,title,description,domain,mastery,prerequisites,enables,retrieval_questions,aliases,topics"
assert_contains "$concepts_csv" "notes/hippocampus.md,hippocampus,Medial temporal lobe structure central to episodic memory and spatial context binding,neuroscience,developing"
```

- [ ] **Step 2: Run VaultIndex test to verify it fails**

Run:

```bash
scripts/tests/test-vault-index.sh
```

Expected: FAIL because `concepts` summary and `vault-index-concepts.csv` do not exist.

- [ ] **Step 3: Add concept summary count**

In `plugins/hippocampusmd/scripts/vault_index.py`, update the `summary` dict:

```python
"concepts": sum(1 for note in notes if str(note["note_type"]).lower() == "concept"),
```

Place it next to `content_notes` and `mocs`.

- [ ] **Step 4: Add concept CSV export**

In `write_csv_exports`, before `vault-index-links.csv`, add a new CSV spec:

```python
(
    "vault-index-concepts.csv",
    [
        "path",
        "title",
        "description",
        "domain",
        "mastery",
        "prerequisites",
        "enables",
        "retrieval_questions",
        "aliases",
        "topics",
    ],
    [
        {
            "path": note["path"],
            "title": note["title"],
            "description": note["description"],
            "domain": note["frontmatter"].get("domain", ""),
            "mastery": note["frontmatter"].get("mastery", ""),
            "prerequisites": note["frontmatter"].get("prerequisites", []),
            "enables": note["frontmatter"].get("enables", []),
            "retrieval_questions": note["frontmatter"].get("retrieval_questions", []),
            "aliases": note["aliases"],
            "topics": note["topics"],
        }
        for note in payload["notes"]
        if str(note["note_type"]).lower() == "concept"
    ],
),
```

This uses existing `write_csv` behavior, which already JSON-encodes lists.

- [ ] **Step 5: Add concept section to Markdown export**

In `write_markdown_export`, add:

```python
concept_rows = [
    {
        "path": note["path"],
        "title": note["title"],
        "domain": note["frontmatter"].get("domain", ""),
        "mastery": note["frontmatter"].get("mastery", ""),
        "description": note["description"],
    }
    for note in payload["notes"]
    if str(note["note_type"]).lower() == "concept"
]
```

Add this table after `Notes`:

```python
("Concepts", ["path", "title", "domain", "mastery", "description"], concept_rows),
```

- [ ] **Step 6: Run VaultIndex test to verify it passes**

Run:

```bash
scripts/tests/test-vault-index.sh
```

Expected: `PASS: vault-index checks`.

- [ ] **Step 7: Commit**

```bash
git add plugins/hippocampusmd/scripts/vault_index.py scripts/tests/test-vault-index.sh
git commit -m "feat: export concept notes from vault index"
```

## Task 6: Wire Plugin Checks And Version Bump

**Files:**
- Modify: `scripts/check-codex-plugin.sh`
- Modify: `scripts/tests/test-codex-smoke.sh`
- Modify: `plugins/hippocampusmd/.codex-plugin/plugin.json`

- [ ] **Step 1: Add plugin check paths**

In `scripts/check-codex-plugin.sh`, near the existing template variables, add:

```bash
reference_concept_template="$REPO_ROOT/plugins/hippocampusmd/reference/templates/concept-note.md"
methodology_concept_exception="$REPO_ROOT/plugins/hippocampusmd/methodology/topic-titled concept notes are valid when the note models a learnable entity.md"
```

Near the existing reference file checks, add:

```bash
if [[ -f "$reference_concept_template" ]]; then
  emit PASS "Reference concept-note template exists."
else
  emit FAIL "Reference concept-note template is missing."
fi

if [[ -f "$methodology_concept_exception" ]]; then
  emit PASS "Concept-note title exception methodology note exists."
else
  emit FAIL "Concept-note title exception methodology note is missing."
fi
```

- [ ] **Step 2: Add smoke test assertions**

In `scripts/tests/test-codex-smoke.sh`, after existing plugin output assertions for reference/template checks, add:

```bash
assert_contains "$plugin_output" "PASS Reference concept-note template exists."
assert_contains "$plugin_output" "PASS Concept-note title exception methodology note exists."
```

- [ ] **Step 3: Bump plugin patch version**

In `plugins/hippocampusmd/.codex-plugin/plugin.json`, change:

```json
"version": "1.0.0",
```

to:

```json
"version": "1.0.1",
```

Patch is appropriate because this is a backwards-compatible setup/docs/indexing improvement that refreshes the installed plugin.

- [ ] **Step 4: Run plugin smoke tests**

Run:

```bash
scripts/check-codex-plugin.sh
scripts/tests/test-codex-smoke.sh
```

Expected: both pass. `check-codex-plugin.sh` may warn if the local plugin cache has not yet been refreshed to `1.0.1`; that warning is acceptable before reinstall.

- [ ] **Step 5: Refresh local plugin cache**

Run the repo's accepted plugin refresh workflow. If this repo continues using manual copy into the Codex plugin cache, use the same pattern as prior work but with the new versioned cache path:

```bash
/bin/cp -R plugins/hippocampusmd /Users/hlee/.codex/plugins/cache/hippocampusmd/hippocampusmd/1.0.1
```

If `scripts/check-codex-plugin.sh` reports a different expected cache path, use that exact path instead.

- [ ] **Step 6: Re-run plugin check after refresh**

Run:

```bash
scripts/check-codex-plugin.sh
```

Expected: PASS for cache exists for `hippocampusmd 1.0.1`.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-codex-plugin.sh scripts/tests/test-codex-smoke.sh plugins/hippocampusmd/.codex-plugin/plugin.json
git commit -m "chore: refresh plugin checks for concept notes"
```

## Task 7: Full Verification And Issue Close

**Files:**
- No planned source changes unless verification exposes a defect.

- [ ] **Step 1: Run focused tests**

Run:

```bash
scripts/tests/test-setup-vault.sh
scripts/tests/test-vault-index.sh
scripts/tests/test-reduce-skill.sh
scripts/tests/test-learn-skill.sh
scripts/tests/test-reflect-skill.sh
scripts/tests/test-validate-skill.sh
scripts/tests/test-index-skill.sh
scripts/tests/test-codex-smoke.sh
```

Expected: every command exits 0 and prints its `PASS:` line.

- [ ] **Step 2: Run broad plugin validation**

Run:

```bash
scripts/check-codex-plugin.sh
```

Expected: no FAIL lines. Cache warnings are not acceptable after Task 6 Step 5.

- [ ] **Step 3: Run git status review**

Run:

```bash
git status --short
```

Expected: only intentional changed files are present. Ignore pre-existing untracked `.obsidian/` if it is still present and unrelated.

- [ ] **Step 4: Commit verification fixes if any exist**

If verification caused additional changes, inspect the changed files:

```bash
git status --short
```

Then stage only the files changed to fix concept-note support. The expected candidates are:

```bash
git add plugins/hippocampusmd/reference plugins/hippocampusmd/generators plugins/hippocampusmd/presets plugins/hippocampusmd/scripts plugins/hippocampusmd/skills scripts/tests scripts/check-codex-plugin.sh plugins/hippocampusmd/.codex-plugin/plugin.json
git commit -m "fix: stabilize concept note support"
```

If there were no additional changes, skip this commit.

- [ ] **Step 5: Close the GitHub issue**

Close issue #53 only after all acceptance criteria pass and all implementation commits exist:

```bash
gh issue close 53 --repo hojaeklee/hippocampusmd --comment "Implemented topic-titled concept notes as an explicit `type: concept` exception with generated research templates, skill guidance, VaultIndex concept exports, tests, and plugin refresh."
```

Expected: GitHub marks issue #53 closed.

## Acceptance Criteria Coverage

- Methodology clearly distinguishes claim notes, topic maps/MOCs, and topic-titled concept notes.
  - Covered by Tasks 1 and 2.
- Research or mixed research-learning vaults can generate a concept-note template during setup or configuration.
  - Covered by Task 3.
- Agent instructions explicitly allow topic-titled concept notes only for `type: concept` notes.
  - Covered by Tasks 2 and 4.
- Reduce/learn guidance includes when to create concept notes versus claim notes.
  - Covered by Task 4.
- Validation/indexing guidance supports discovering all concept notes through `type: concept`.
  - Covered by Tasks 4 and 5.
- Tests or fixture updates cover the new convention.
  - Covered by Tasks 3, 4, 5, and 6.

## Residual Risks

- This plan does not add a full Learning preset. It intentionally creates reusable concept-note support first.
- Existing vaults will not automatically receive `templates/concept-note.md`; users can rerun setup only if it is idempotent and missing-file filling is desired, or copy the generated template manually.
- Validation will document the exception but will not enforce title grammar in this pass. A future issue can add deterministic title-shape checks if needed.
- Obsidian Bases integration remains documentation/export-friendly only. The repo exports concept metadata but does not create an Obsidian Base file.
