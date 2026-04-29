---
id: ir-krae
status: closed
deps: []
links: []
created: 2026-04-29T05:15:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3asf
tags: [area:live-fragments, source:plans-62]
---
# Bridge live surfaces and projection definitions

Unify LiveSurfaceDefinition and SurfaceProjectionDefinition so projection-backed surfaces reuse the same fragment enum/ref mapping and expose standard load/render/warm helpers.

## Acceptance Criteria

Projection-backed surfaces can render and broadcast through LiveSurfaceDefinition without duplicating fragment-ref builders in SurfaceProjectionDefinition.

