---
id: ir-gwjb
status: closed
deps: [ir-jxle]
links: []
created: 2026-07-09T10:10:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, admin, live]
---
# Add admin venue time-picker window controls

Expose the venue picker window in Admin Venue Settings and persist validated changes.

## Design

Add start/end time controls to the existing Admin Venue Settings surface. Validate submitted HH:MM quarter-hour values server-side, allow overnight ranges, reject malformed or zero-length windows with local feedback, and invalidate admin settings plus roster/timesheet picker-dependent resources.

## Acceptance Criteria

Venue admins can save a valid overnight picker window. Invalid or non-quarter-hour submissions produce controlled feedback. Admin settings refresh correctly through the existing live/HTMX surface path.

