---
id: ir-rs8u
status: open
deps: []
links: []
created: 2026-05-21T07:00:19Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-uir5
tags: [agent-loop, area:architecture, area:live-fragments, area:performance]
---
# Document projection and viewer-state cache boundaries

Record the current projection/cache contract and the boundary between shared snapshots and viewer-specific render state.

## Design

Document the invariant: anything user/session-specific that affects a cached projection snapshot or rendered projection fragment must either be included in the projection viewerKey or applied outside the cached snapshot at the final render boundary. Inventory current roster viewer-specific fields: layout mode, assignment filters, staff self-service panel, wage prediction visibility/capabilities, and future display preferences such as shift-type highlights. Explain why display preferences are safer as final render inputs, while expensive viewer-derived data may need separate derived caching. Update the most appropriate living docs, likely Application/Helper/LiveUpdate.SPEC.md, Application/Helper/LiveSurface.COOKBOOK.md, Web/RosterWeeks/SPEC.md, or docs/workstreams/backlog.md.

## Acceptance Criteria

Living docs state the projection viewerKey/final-render invariant, identify current roster viewer-state examples, and give guidance for future preference additions. The docs explicitly say not to put new user display preferences into RosterRenderData unless viewerKey/currentVersion semantics are updated. ir-jooi is referenced as related historical projection-cache work.

