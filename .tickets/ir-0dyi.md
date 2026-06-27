---
id: ir-0dyi
status: closed
deps: [ir-r98d]
links: []
created: 2026-06-27T09:16:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lcpr
tags: [agent-loop, live-surface, interaction]
---
# Attach interaction metadata through surface descriptors

Make optional interaction schema/capability attachment a first-class descriptor modifier so live + interaction declarations share one canonical surface origin.

## Acceptance Criteria

Roster interaction metadata can be expressed through the descriptor path or an adapter without changing generated contracts.


## Notes

**2026-06-27T09:40:59Z**

Added liveSurfaceDescriptorWithInteraction so interaction static schema and capability can be attached as a descriptor modifier before lowering to TypedLiveSurfaceDefinition. Added helper coverage proving descriptor-attached interaction metadata survives lowering. Roster already exposes interaction metadata through its typed surface registration adapter. Verification passed: typecheck and focused LiveSurface helper Hspec.
