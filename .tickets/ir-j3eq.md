---
id: ir-j3eq
status: open
deps: []
links: [ir-u4mc, ir-tfed]
created: 2026-05-28T05:35:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:leave, area:timesheets, area:xero, area:ui, agent-loop]
---
# Unavailability, timesheet card, and Xero page polish

Clean up leave/unavailability actions, a timesheet card wrapping issue, and disconnected Xero-page behavior.

## Design

Decisions from 2026-05-28 notes:
- Remove unavailability delete semantics entirely: visible buttons, route/action/type/route registration, and tests should be deleted rather than retaining a soft-delete duplicate of deny.
- Keep in mind the archive will grow indefinitely; add a follow-up/pagination note or child ticket when implementing.
- On Unavailability only, keep the top Pending accordion section open by default; other accordion pages should generally default closed.
- Remove the Actions column from the unavailability Archive section.
- Prevent the timesheet card Break line from wrapping awkwardly.
- If there is no active Xero connection, the Xero page should show only the connection card at the top; timesheet submission/mapping/pay item sections stay hidden until connected/active.
- Replace customer-facing 'IHP'/'ihp-roster' product copy in the Xero page with 'Bepis'.

Implementation steps:
1. Remove DeleteLeaveRequestAction and related UI/tests/routes, preserving status lifecycle and existing deny behavior.
2. Split archive rendering so it has no action header/cell, and record a pagination follow-up for the archive.
3. Add narrow CSS or markup to keep the timesheet Break meta line intact.
4. Adjust Xero view rendering so disconnected/inactive state shows only the connection card.
5. Replace customer-facing IHP product copy in Xero timesheet text with Bepis and update tests.

## Acceptance Criteria

Unavailability no longer exposes or routes delete; Pending remains the only default-open accordion section; Archive has no Actions column; timesheet Break text stays on one line; disconnected/inactive Xero page shows only connection chrome; customer-facing Xero copy says Bepis; focused tests are updated.

