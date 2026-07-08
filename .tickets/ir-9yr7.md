---
id: ir-9yr7
status: closed
deps: []
links: []
created: 2026-07-08T09:28:50Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:payroll, area:fwc, area:schema, agent-loop]
---
# Add central venue-effective award-rate resolution helpers

Introduce shared semantics for deriving Bepis venue-effective award-rate dates from raw FWC operative dates and resolving the applicable rate for a venue/reference date.

## Design

Add Haskell helper(s) for venue-effective date derivation and rate selection. Add SQL helper function(s) or a reusable SQL pattern for calculate_timesheet_pay. Rule: NULL operative_from remains undated/default; otherwise the effective date is the first venue week-start date greater than or equal to the raw FWC operative_from date.

## Acceptance Criteria

Focused tests cover a Monday venue week with a Wednesday FWC operative date; helper returns following Monday for Wednesday and same day for Monday; terminology distinguishes raw FWC operative date from Bepis venue-effective date.

