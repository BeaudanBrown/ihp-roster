---
id: ir-omzt
status: open
deps: []
links: []
created: 2026-05-08T04:22:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, api]
---
# Add Xero Pay Runs API and selectable payroll periods

Add first-class Xero Payroll AU Pay Runs support and use it to build selectable pay-period options for draft-timesheet preparation.

## Design

Extend Application.Helper.Xero with XeroPayRunRef, response parsing, request builders, fetchPayRuns, pagination, and strict contract/mock coverage. Combine synced payroll calendars, pay runs, and remote timesheets into period options. Show what Xero returns for historical periods; add diagnostics for any real-world lookback/API limits rather than assuming a fixed range.

## Acceptance Criteria

Pay runs can be fetched through the Xero client boundary; period options include calendar id/name, start/end, payment date where known, pay-run id/status where known, and blocking state for POSTED periods. Existing contract tests cover request shape and response decoding.

