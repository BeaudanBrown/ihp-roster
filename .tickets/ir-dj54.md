---
id: ir-dj54
status: closed
deps: [ir-fh80, ir-dhl7]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, docs]
---
# Document final generated interaction and surface architecture

Update living docs after implementation to describe the final generated manifest/ref runtime, helper layers, and surface vocabulary.

## Design

Update `Application/Helper/Interaction.SPEC.md`, `Application/Helper/FrontendSurface/README.md`, relevant `AGENTS.md`, and workstream indexes if needed. Include how to add a new interactive surface, source/dropzone/activation examples, the DOM-owned HTMX form rule, browser runtime responsibilities, guardrails, non-goals, and deletion of the legacy semantic marker protocol.

## Acceptance Criteria

- Docs explain how to add a new interactive surface without raw semantic marker wiring.
- Docs match implemented APIs and tests.
- Final architecture clearly separates generated semantics, server-owned forms, and generic browser runtime.
- Epic acceptance criteria can be verified and closed.
