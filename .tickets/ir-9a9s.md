---
id: ir-9a9s
status: closed
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


## Notes

**2026-06-27T07:17:52Z**

Added LiveSurface strict guard coverage that scans migrated simple descriptor-backed surface modules and fails if they reintroduce the raw TypedLiveSurfaceDefinition record constructor. Complex surfaces remain outside this guard. Verification passed: typecheck and focused LiveSurface strict API guard Hspec.
