---
id: ir-gj02
status: closed
deps: []
links: []
created: 2026-05-22T06:52:44Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-h2xi
tags: [area:live-fragments]
---
# Consolidate live fragment metadata into FragmentContract

Replace parallel typedSurfaceFragmentRef and typedSurfaceDependsOn declarations with one typedSurfaceFragmentContract record field.

## Acceptance Criteria

All surfaces compile through FragmentContract; existing helper functions are derived for compatibility; focused live-surface tests pass.


## Notes

**2026-05-22T07:01:55Z**

Implemented: introduced FragmentContract and typedSurfaceFragmentContract as the single declaration point for ref/dependencies; derived typedLiveSurfaceFragmentRef, typedSurfaceDependsOn, projection refs, actor refresh, resync, and passive planning from the contract. Migrated all typed live surfaces and added LiveSurface coverage for deriving refs/dependencies from one contract. Verification: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LiveSurface' --match 'SurfaceProjection' (13 examples).
