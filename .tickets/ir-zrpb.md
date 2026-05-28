---
id: ir-zrpb
status: in_progress
deps: [ir-1d53]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-5n96
tags: [area:roster, area:timesheets, area:ui]
---
# Convert roster and timesheet toggles to shared buttons

Migrate high-visibility roster and timesheet toggles from switch UI to the shared green button pattern.

## Design

Cover roster live, roster staff scope, roster wage-estimate/assignment-filter toggles, timesheet hide-approved/show-all-staff, and timesheet dialog break toggle if it remains a binary toggle UI. Preserve HTMX targets, hidden query state, onchange/requestSubmit semantics, and labels.

## Acceptance Criteria

Roster and timesheet pages contain no form-switch markup for these controls; interactions update fragments/query params as before; mobile screenshots show green active/inactive buttons.

