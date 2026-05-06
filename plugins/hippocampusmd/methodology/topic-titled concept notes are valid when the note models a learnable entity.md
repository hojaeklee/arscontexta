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
