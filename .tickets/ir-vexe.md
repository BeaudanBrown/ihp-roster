---
id: ir-vexe
status: closed
deps: [ir-9lol]
links: []
created: 2026-07-04T04:34:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lnxp
tags: [agent-loop, surfaces, docs, naming]
---
# Polish remaining stale surface naming and docs

Clean low-risk stale LiveSurface names and active docs now that the architecture is FrontendSurface-native.

## Design

Rename obvious local identifiers such as supportLiveSurface/profileLiveSurfaceId/rosterStaffSelfServiceTimesheetLiveSurfaceId where low-risk. Update active docs/workstream indexes so old typed-live-surface migration narratives are archived or clearly historical. Avoid churning archived docs unless they confuse active guidance.

## Acceptance Criteria

Non-archive active docs and low-risk identifiers use FrontendSurface/Surface vocabulary. Historical references are either archived or explicitly historical. doc-drift-check and typecheck pass.

