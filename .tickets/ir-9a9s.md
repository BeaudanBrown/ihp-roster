---
id: ir-9a9s
status: open
deps: [ir-3buk]
links: []
created: 2026-06-27T06:57:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-8476
tags: [agent-loop, live-surface, test]
---
# Add simple surface authoring guardrails

Add tests to prevent migrated simple surfaces from regressing to full raw TypedLiveSurfaceDefinition constructors.

## Acceptance Criteria

Guardrails allow complex surfaces but fail if simple migrated modules hand-write the full constructor again.

