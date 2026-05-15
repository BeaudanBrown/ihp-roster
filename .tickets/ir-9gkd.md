---
id: ir-9gkd
status: open
deps: []
links: []
created: 2026-05-08T04:22:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, schema]
---
# Persist Xero timesheet preparation runs and approval decisions

Model preparation runs separately from submission runs so modal preparation can stop, resume, and audit decisions before preview/submission.

## Design

Add preparation-run persistence for selected period, connection, remote pay-run/timesheet snapshots, readiness snapshot, status, events, proposed actions, and run-scoped staff skips. Keep persistent staff mapping/not-paid decisions in existing xero_staff_mappings where possible. Use schema/types as source of truth and regenerate types after schema changes.

## Acceptance Criteria

Preparation run records can store pending/proposed/applied/blocked/resolved states. Proposed staff mappings, manual dropdown choices, not-paid-through-Xero decisions, run-scoped skips, payroll calendar/account-code choices, and pay-item create approvals are represented without overloading xero_submission_runs.

