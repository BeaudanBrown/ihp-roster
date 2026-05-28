---
id: ir-kjc9
status: open
deps: []
links: [ir-caf4, ir-9jap]
created: 2026-05-28T05:35:32Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:roster, area:validation, area:ui, agent-loop]
---
# Roster day-window validation and publish feedback cleanup

Tighten roster shift time semantics and make failed publish attempts visually actionable.

## Design

Decisions from 2026-05-28 notes:
- The roster operational day window is 06:00 through 05:45 the next morning.
- Time-picker ranges, duration calculation, publish validation, wage prediction, roster-to-timesheet automation, and tests should share one source of truth for that window.
- Overnight shifts inside that window are valid; end times that imply an invalid/non-positive/out-of-window shift should be rejected or block publish.
- After a go-live attempt fails due to missing roster fields, the affected start/end/shift-type controls should render warning/red state so the user can find and fix them.
- Roster JPG export remains available but only on live rosters, with regression coverage.

Implementation steps:
1. Extract shared day-window constants/helpers in the time rules layer and align the time picker end range with 05:45.
2. Apply the shared duration/window rules to roster slot create/update, publish validation, wage prediction eligibility, and roster timesheet automation as needed.
3. Thread publish validation state into roster render data or another explicit feedback path so missing required fields render red after failed go-live.
4. Gate the roster export menu item on live roster state.
5. Add focused Hspec for helper/controller behavior and Playwright coverage for failed publish field highlighting and live-only export visibility.

## Acceptance Criteria

Roster shifts use a consistent 06:00-05:45 operational-day window; invalid end/start combinations cannot be saved or published silently; failed publish attempts mark missing required roster fields visibly; roster JPG export is visible only when the week is live; focused tests cover the new behavior.

