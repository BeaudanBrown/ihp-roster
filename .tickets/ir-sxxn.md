---
id: ir-sxxn
status: open
deps: [ir-w9dw]
links: []
created: 2026-07-01T01:40:01Z
type: chore
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, docs]
---
# Document final generic frontend contract architecture

Update durable docs and agent notes to describe the final generic DTO contract architecture and extension workflow.

## Design

Update Application/Helper/Frontend/README.md, Application/Helper/Interaction.SPEC.md, Application/Helper/LiveUpdate.SPEC.md, Application/Helper/LiveSurface.COOKBOOK.md, frontend/AGENTS.md, static/AGENTS.md, and architecture/workstream docs as needed. Explain DTO module layout, generic codec derivation, contract groups, generated type/guard/parse/encode output, JSON-shaped DTO rule, adding a new live surface, adding an interaction intent, no manual/legacy generation, and future HIE/GHC API verification path.

## Acceptance Criteria

Docs accurately describe the implemented final system. doc-drift-check passes if applicable. The workstream can be marked implemented/archived after all child tickets close and durable behavior is moved into local docs/specs.

