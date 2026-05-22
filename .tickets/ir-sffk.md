---
id: ir-sffk
status: closed
deps: [ir-gj02]
links: []
created: 2026-05-22T06:52:44Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-h2xi
tags: [area:live-fragments]
---
# Make live fragment dependency choices explicit

Replace bare dependency lists in FragmentContract with an explicit dependency declaration such as DependsOn/ResyncOnly.

## Acceptance Criteria

Each fragment declares either live resources or an intentional resync-only reason; affected-fragment planning remains unchanged for dependent fragments.


## Notes

**2026-05-22T07:08:09Z**

Implemented: FragmentContract now carries FragmentDependencies instead of a bare list. Added liveFragmentDependsOn for non-empty resource dependencies and liveFragmentResyncOnly for fragments with intentional no passive dependency. Migrated all surfaces; profile security and surface-projection test fragments now declare resync-only intent explicitly. Verification: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LiveSurface' --match 'SurfaceProjection' (14 examples).
