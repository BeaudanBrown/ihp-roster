---
id: ir-d4bn
status: open
deps: []
links: []
created: 2026-05-22T01:34:04Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:roster, area:payroll, ui, agent-loop]
---
# Integrate predicted wages into roster headers

Move predicted roster wage totals out of the always-visible top panel and into contextual roster chrome: week total in the roster toolbar and day totals in day labels/headers for both roster layouts.

## Design

Preserve existing admin-only data fetching and permissions. Remove the full-width roster-wage-prediction panel above the grid. Render a compact admin-only week summary in the roster toolbar/header, e.g. Predicted wages: $420.00. If predictionIncompleteShiftCount > 0, append compact static warning copy, e.g. 3 draft shifts excluded. Render per-day totals in the standard row-layout day rail and in day-column layout headers. Do not add JavaScript, toggles, persisted visibility preferences, or popovers. Keep wage predictions separate from final payroll/Xero output without forcing a large always-visible disclaimer into the UI.

## Acceptance Criteria

Admins see week predicted wages in roster toolbar chrome and daily predicted totals in day headers/labels. Managers/staff without admin permission do not see predicted wage markup or totals. The existing full-width predicted wage panel no longer appears above the roster grid. Both roster layouts show daily totals without breaking desktop/mobile layout. Draft rosters with incomplete staffed shifts show a compact excluded-shifts warning. Live roster publishing rules remain unchanged. Existing wage calculation behavior is unchanged.


## Notes

**2026-05-22T01:48:57Z**

HANDOFF from ir-ie9a: Header now accepts Maybe RosterWagePrediction; day render models carry dayRosterWagePrediction; Application.Helper.RosterWagePrediction exports lookup helpers for day totals.

**2026-05-22T01:55:04Z**

HANDOFF from ir-3d73: Compact predicted wage markup is now in toolbar/day headers using roster-wage-summary and roster-day-wage-total; old full-width panel renderer is removed, while detailed styling/regression coverage remains for ir-xkjl.
