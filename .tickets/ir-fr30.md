---
id: ir-fr30
status: closed
deps: []
links: []
created: 2026-07-07T03:54:40Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-6rnm
tags: [agent-loop, roster, timeline]
---
# Add roster day timeline route, shell, entry links, and permissions

Add the navigable single-day timeline entry point and basic shell before implementing timeline rendering or drag behavior.

## Design

Add a ShowRosterDayTimeline-style action and path helper scoped by weekOffset, rosterGroupId, and rosterDayId. Add small Timeline links near each day name/date in both day-row and day-column views. Render a timeline page shell with a Back to week view link preserving weekOffset and rosterGroupId. Reuse existing roster visibility rules: managers/admins may view draft or live, managers/admins edit only draft/unpublished, staff may view only live/published, and staff never edit.

## Acceptance Criteria

Managers/admins can open the timeline shell for draft and live weeks. Staff can open only live/published timeline views and draft staff access is denied or hidden consistently with existing roster behavior. Back to week returns to the canonical roster week URL with rosterGroupId and weekOffset. No drag behavior is required in this ticket.

