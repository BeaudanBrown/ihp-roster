---
id: ir-xkjl
status: open
deps: [ir-3d73]
links: []
created: 2026-05-22T01:34:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-d4bn
tags: [area:roster, area:payroll, ui, agent-loop, chunk]
---
# Restyle predicted wage chrome and cover roster regressions

Polish the integrated predicted wage UI and update tests/docs for the new placement.

## Design

Add/update focused CSS in static/css/features/roster.css for the toolbar summary and day-header/day-rail wage totals. Remove obsolete roster-wage-prediction panel CSS if no longer used. Update focused Hspec assertions from the old panel text to the new toolbar/day markup. Capture or manually inspect screenshots for standard and day-column layouts where practical. Update Web/RosterWeeks/SPEC.md or the Rooks pilot workstream if the implemented UI contract needs living documentation.

## Acceptance Criteria

bash ./bin/in-env typecheck passes. Focused roster Hspec for predicted wages passes. Visual check or screenshot confirms no obvious desktop/mobile crowding in standard and day-column layouts. Relevant living docs reflect the new UI contract if changed.

