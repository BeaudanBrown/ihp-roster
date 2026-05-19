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

Add preparation-run persistence for selected period, connection, selected Xero payroll calendar id/name, pay-period start/end, payment date, pay-run id/status, remote pay-run/timesheet snapshots, readiness snapshot, status, events, proposed actions, and run-scoped staff skips. Keep persistent staff mapping/not-paid decisions in existing `xero_staff_mappings` where possible. Use schema/types as source of truth and regenerate types after schema changes.

Preparation persistence should represent the modal workflow decisions without making `xero_submission_runs` carry pre-submission state. Persist the selected calendar/window as run metadata, not as a venue-global calendar choice. Persist account-code/pay-item decisions only when they are real user or deterministic system decisions. Do not require or populate `xero_payroll_calendar_selections` for modal preparation; if old global selection code still exists, it is legacy/default state outside this ticket.

## Acceptance Criteria

Preparation run records can store pending/proposed/applied/blocked/resolved states and enough selected-period metadata for later readiness, preview, duplicate-check, and submission steps to run without URL params or global calendar selection. Proposed staff mappings, manual dropdown choices, persistent not-paid-through-Xero decisions, run-scoped skips for unmapped staff, account-code choices, and pay-item create approvals are represented without overloading `xero_submission_runs`.

