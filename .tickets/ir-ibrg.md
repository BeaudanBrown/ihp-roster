---
id: ir-ibrg
status: open
deps: [ir-kjht]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, reference-sync]
---
# Sync MYOB employees wage categories accounts and payroll details

Implement MYOB reference data sync into provider-neutral reference tables.

## Design

Fetch and persist MYOB employees, employee payroll details, wage payroll categories, and general ledger accounts needed for pay item setup and timesheet submission. Preserve raw payloads, RowVersion/UID metadata, statuses, cftoken requirements, sync run audit state, stale detection, and pagination.

## Acceptance Criteria

Payroll UI can render MYOB employees, wage categories, accounts, and employee payroll-detail readiness from provider-neutral read models. Sync failures are auditable and actionable. Tests cover upsert/stale behavior and representative MYOB payloads.

