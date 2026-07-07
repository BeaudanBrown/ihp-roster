---
id: ir-4mse
status: open
deps: [ir-qq35]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-elys
tags: [docs, frontend-contracts, htmx]
---
# Document FrontendSurface action contract pattern

Record the reusable pattern for future surface migrations.

## Design

Update FrontendContract/Surface docs and Web/View agent guidance with the route-construction split: DSL owns semantic action metadata; Haskell route instances own IHP paths; generated TS validates action metadata. Include the Admin Roster Groups example and guidance for what does not belong in SurfaceAction.

## Acceptance Criteria

Docs explain how to add a new generated surface action and when not to use this system. Future migrations have a clear checklist.

