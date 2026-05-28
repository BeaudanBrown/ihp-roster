---
id: ir-1e9i
status: open
deps: []
links: [ir-63z2]
created: 2026-05-28T05:35:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:roster, area:mobile, area:ui, agent-loop]
---
# Roster header and mobile week-control polish

Simplify roster week chrome while keeping mobile controls stable and temporarily disabling the month overview.

## Design

Decisions from 2026-05-28 notes:
- Replace the roster month-overview dropdown with a non-clickable week label for now. Keep overview code available for later re-enable.
- Move the wage summary to the right side of the roster header/toolbar.
- Shorten wage labels/badges to use 'Wages' language instead of 'Wage estimate'.
- Keep the closed-day control fixed/stable in day-column layout.
- Center the 'This week' control for mobile roster clients.

Implementation steps:
1. Adjust roster header rendering to use a static week label instead of renderWeekOverviewDropdown.
2. Update shared week toolbar CSS/layout only as needed to preserve timesheet behavior while moving roster auxiliary content right.
3. Update wage summary/day labels and associated assertions.
4. Stabilize day-column closed control positioning in roster CSS.
5. Refresh responsive Playwright coverage for roster toolbar ordering and mobile closed-button behavior.

## Acceptance Criteria

Roster week label is non-clickable; wage chrome appears in the intended right-side header area with shortened copy; day-column closed control remains stable; mobile 'This week' is centered; roster/timesheet toolbar regressions are covered.

