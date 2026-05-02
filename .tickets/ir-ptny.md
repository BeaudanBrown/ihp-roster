---
id: ir-ptny
status: open
deps: [ir-rob3]
links: []
created: 2026-05-02T01:12:06Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:roster, area:payroll, area:pilot, venue:rooks]
---
# Show admin-only predicted roster wage totals

## Design

Expose predicted wage totals from the roster page for admin-and-up users. V1 output is per-day totals plus week total only. Prediction uses rostered staff, start/end datetimes, shift type, existing pay rules, and an assumed 30-minute unpaid break for shifts over 6 hours. This is a prediction surface, not final payroll.

Workstream: `docs/workstreams/rooks-pilot.md`

## Acceptance Criteria

Admins can view per-day and week predicted wage totals from roster context; non-admin managers/staff cannot see wage totals; totals handle overnight shifts; calculations assume a 30-minute unpaid break for shifts over 6 hours; output is clearly separate from approved timesheet/Xero payroll submission.
