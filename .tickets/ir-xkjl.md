---
id: ir-xkjl
status: closed
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


## Notes

**2026-05-22T02:01:32Z**

HANDOFF: Polished compact predicted wage toolbar/day-header CSS, removed obsolete full-width panel styles, strengthened roster Hspec assertions, and documented the admin-only roster chrome contract; tests run: bash ./bin/in-env typecheck, bash ./bin/in-env hspec-test --match "RosterWeeks", git diff --check, screenshots captured for day_rows and day_columns at output/ir-xkjl/; remaining risk: screenshots use seeded dev data with zero-dollar wage totals because seeded draft shifts lack complete prediction inputs.
