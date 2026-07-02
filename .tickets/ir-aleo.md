---
id: ir-aleo
status: open
deps: [ir-4hu6, ir-xopg, ir-8w6w]
links: []
created: 2026-07-02T02:47:03Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, timesheets]
---
# Migrate Timesheets to FrontendSurface spec

After the lab proves the foundation, express the existing timesheets frontend behavior as a type-level FrontendSurface.

## Design

Model timesheet_week scope, toolbar/day columns/day section fragments, candidate day sections, HTMX/filter actions, resources, authorization, projection version bridge, and mount rendering through SurfaceImpl.

## Acceptance Criteria

Timesheets generated contracts come from the surface spec and the old frontend contract machinery is not used for the migrated timesheets surface.

