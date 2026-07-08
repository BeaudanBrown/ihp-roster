---
id: ir-sc3c
status: open
deps: [ir-zi2e]
links: []
created: 2026-07-08T07:20:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jvjj
tags: [frontend-contracts, typescript, surface, live-update]
---
# Derive surface mount/live adapter schemas from Haskell carriers

Replace handwritten FrontendSurfaceMountConfig, mounted-fragment, live-fragment, live-subscription, and protection TypeScript shapes with schemas derived from Haskell carrier types or existing LiveUpdateContract types.

## Design

Use existing FrontendSurfaceMountConfig/FrontendSurfaceMountedFragment Haskell carriers and LiveUpdateContract SurfaceFragmentProtection/SurfaceWireFragment where possible. Decide whether mount config becomes an explicit generated DTO schema or whether parsing/normalization moves to frontend runtime code importing generated primitive types.

## Acceptance Criteria

Generated mount/live adapter types reflect Haskell carrier schemas; no stale manual fields can diverge from Runtime.hs/Wire.LiveUpdate; live-update frontend tests pass.

