---
id: ir-vgdg
status: open
deps: []
links: []
created: 2026-04-30T06:56:32Z
type: task
priority: 1
assignee: beaudan
parent: ir-hw2v
tags: [area:payroll, area:schema]
---
# Design append-only pay config version schema

Design the relational tables and constraints that replace JSON pay snapshots for pay reproducibility.

## Design

Define version tables for shift type pay mapping, staff pay assignment/employment basis, accepted award/rate releases, and export/submission membership/locks. Include effective dating, supersession, locked_at/locked_by_user_id where needed, tenant constraints, and IHP parser-safe checks/enums.

## Acceptance Criteria

Plan and schema proposal identify every pay-relevant mutable field currently used by calculate_timesheet_pay/export/Xero; new version rows cover those facts; mutation/locking semantics are documented before migration implementation.

