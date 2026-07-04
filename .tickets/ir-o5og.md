---
id: ir-o5og
status: open
deps: [ir-2j46]
links: []
created: 2026-07-04T01:20:55Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-7jqj
tags: [agent-loop, surfaces, timesheets]
---
# Remove timesheets legacy live surface config

Delete timesheetsLegacyLiveSurfaceConfig and move remaining timesheets/staff-self-service consumers to FrontendSurface mount/subscription config.

## Design

Replace LiveSurfaceConfig compatibility usage with SurfaceImpl/FrontendSurfaceMountConfig and generated subscription metadata. Preserve request decoration and resync behavior through the FrontendSurface runtime contract, not the old LiveSurfaceConfig DTO.

## Acceptance Criteria

No timesheetsLegacyLiveSurfaceConfig remains; Web.Timesheets.FrontendSurface does not import Application.Helper.LiveSurface; timesheets/staff self-service tests pass.

