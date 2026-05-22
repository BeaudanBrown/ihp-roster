---
id: ir-ie9a
status: closed
deps: []
links: []
created: 2026-05-22T01:34:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-d4bn
tags: [area:roster, area:payroll, ui, agent-loop, chunk]
---
# Thread wage prediction into roster header and day render models

Make existing roster wage prediction data available to the roster toolbar and individual day renderers without changing calculation behavior.

## Design

Pass Maybe RosterWagePrediction to renderRosterGridHeader. Add wage prediction access to RosterDayRenderModel, either directly or as a derived day lookup helper. Add small helper(s) to find the matching RosterWagePredictionDay for each rendered day by date/day offset. Preserve existing admin-only fetch behavior.

## Acceptance Criteria

Typecheck passes. Header and day render paths can access wage prediction data. No permissions or calculation behavior changes are introduced. No JavaScript or persistence is added.


## Notes

**2026-05-22T01:48:57Z**

HANDOFF: Threaded Maybe RosterWagePrediction into renderRosterGridHeader and RosterDayRenderModel, including projection/direct day-section fragment render paths; added prediction day lookup helpers by offset/date. Tests: bash ./bin/in-env typecheck passed. Remaining: sibling ir-3d73 can render compact header/day totals using the threaded data and helpers.
