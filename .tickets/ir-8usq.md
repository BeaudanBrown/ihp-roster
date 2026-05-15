---
id: ir-8usq
status: open
deps: [ir-omzt, ir-mjos]
links: []
created: 2026-05-08T04:22:39Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, readiness]
---
# Apply Xero period and duplicate blockers in preparation flow

Harden readiness/preparation around Xero pay-run status and existing remote timesheets.

## Design

Hard-block periods whose Xero pay run is POSTED. For v1, block any existing remote Xero timesheet for the same employee and period, regardless of draft/approved status, until explicit update support lands. Surface clear modal events and keep duplicate snapshots on preparation/submission records.

## Acceptance Criteria

Posted pay runs cannot reach preview. Existing remote employee-period timesheets prevent create and are visible in modal blockers. Tests cover posted pay-run and existing-timesheet blockers.

