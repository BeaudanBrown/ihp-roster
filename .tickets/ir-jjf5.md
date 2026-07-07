---
id: ir-jjf5
status: open
deps: [ir-fr30]
links: []
created: 2026-07-07T03:54:41Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-6rnm
tags: [agent-loop, roster, timeline, surfaces, interaction]
---
# Define roster day timeline FrontendSurface contract and runtime

Declare and implement the typed FrontendSurface contract for the single-day timeline.

## Design

Add a new timeline-oriented roster surface, likely RosterDayTimelineSurface, with scope fields for venue, roster group, week offset, and roster day. Declare live timeline fragment(s), a drag/drop session/refs, and a move timeline shift intent/action using generated FrontendSurface interaction primitives. Implement a SurfaceImpl that owns mount metadata, fragment URLs/targets, HTMX form/action metadata, fields, conflict policy, and resource dependencies without feature-specific TypeScript.

## Acceptance Criteria

Generated contracts include the timeline surface, scope, fragment(s), drag session, source/dropzone refs, move intent fields, layers/effects, and conflict policy. SurfaceImpl handler completeness/typecheck catches missing handlers. No feature-specific browser adapter is introduced. frontend-contracts-check and typecheck pass for this slice.

