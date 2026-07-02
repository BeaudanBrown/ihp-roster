---
id: ir-vutq
status: closed
deps: [ir-c6i9, ir-2o24]
links: []
created: 2026-04-29T04:41:29Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-jooi
tags: [workstream, coordinator:coordinator-2b0, area:performance, area:live-fragments]
---
# Keep the current roster week projection hot and observable

Warm current-week projections and expose enough metrics/logging to see cache effectiveness.


## Notes

**2026-07-02T12:45:35Z**

Superseded by the FrontendSurface/direct read-model refactor: Application.Helper.SurfaceProjection and the roster/leave projection-cache plumbing have been removed. Future caching work must be explicit resource-versioned read-model/cache design behind feature read-model or SurfaceImpl seams, not resurrection of the generic SurfaceProjection helper.
