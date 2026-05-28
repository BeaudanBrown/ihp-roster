---
id: ir-elbv
status: closed
deps: []
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-bao4
tags: [area:view, area:roster, area:timesheets]
---
# Extract reusable week toolbar helper

Create a shared view helper for week toolbars used by roster and timesheets.

## Design

Place helper under Application.Helper.View (or a focused submodule) with config records, not callbacks. Keep feature-specific URL builders in Web.RosterWeeks.Paths and Web.Timesheets.Paths.

## Acceptance Criteria

Roster and timesheet headers call the shared helper for common week toolbar structure; typecheck passes; helper has no feature-specific route assumptions.

