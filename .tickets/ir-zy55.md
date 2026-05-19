---
id: ir-zy55
status: open
deps: []
links: [ir-9u78, ir-shsr, ir-axdb, ir-tfed]
created: 2026-05-08T04:22:46Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-176p
tags: [area:xero, area:payroll, research]
---
# Research Xero draft timesheet update support

Research and document the work required to update existing Xero draft timesheets instead of blocking them.

## Design

Use Xero Payroll AU updateTimesheet contract and, if safe credentials are available, live probes. Determine status mutability, request shape, idempotency behavior, duplicate semantics, how to preserve IHP audit/source-entry history, and how to handle already-approved/posted remote state. Do not implement updates in the modal v1.

## Acceptance Criteria

A note or workstream update documents whether update is viable, required API constraints, local schema/state changes needed, and recommended follow-up implementation tickets.

