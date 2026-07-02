---
id: ir-p3c3
status: open
deps: [ir-npm8]
links: []
created: 2026-07-02T04:59:35Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, live-update, architecture]
---
# Define legacy and FrontendSurface registry coexistence

Define how RegisteredFrontendSurfaces/SurfaceImpl runtime enumeration coexists with Web.LiveSurfaceRegistry and legacy self-describing wire surfaces during migration, and how the final no-legacy, unified mount-resolved target is reached.

## Design

Use one explicit type-level RegisteredFrontendSurfaces list for migrated surfaces and derive runtime enumeration from it via typeclass/fold machinery. Legacy surfaces remain in Web.LiveSurfaceRegistry during migration. Final target migrates all surfaces to the new mount-resolved protocol and removes legacy live paths.

## Acceptance Criteria

The planner/authorization/manifest coexistence model is specified; runtime enumeration comes only from the type-level registry for migrated surfaces; new migrated surfaces cannot use old paths; legacy surfaces remain functional; final unification/removal path is recorded.

