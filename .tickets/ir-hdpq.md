---
id: ir-hdpq
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-j3eq
tags: [area:leave, area:unavailability, agent-loop]
---
# Remove unavailability delete route and UI

Delete the unavailability delete workflow rather than keeping a redundant soft-delete action.

## Design

Remove DeleteLeaveRequestAction from Web.Types, routes, controller, views, and tests. Remove visible Delete buttons/forms from manager and staff unavailability surfaces. Preserve approve/deny lifecycle behavior and live invalidation rules for status changes.

## Acceptance Criteria

No DeleteLeaveRequest route/action exists; unavailability views do not render delete controls; tests no longer assert delete behavior and instead cover approve/deny where relevant; typecheck passes.

