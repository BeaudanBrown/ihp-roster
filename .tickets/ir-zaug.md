---
id: ir-zaug
status: closed
deps: []
links: []
created: 2026-06-27T06:57:15Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-8476
tags: [agent-loop, live-surface]
---
# Add live fragment builder helpers

Add small helpers around LiveFragmentDescriptor/mkSurfaceFragmentRef for static fragment refs, protection, containment paths, and current-venue resource dependencies.

## Acceptance Criteria

Helpers compile and focused LiveSurface contract tests cover target ids, resources, protection, and containment paths.


## Notes

**2026-06-27T07:01:54Z**

Added fragment builder helpers: staticLiveFragmentDescriptor, currentVenueLiveFragmentDescriptor, descriptor modifiers for protection/defer/path/target id, plus tests for protection, containment, and target retargeting. Verification passed: typecheck and focused LiveSurface contract Hspec.
