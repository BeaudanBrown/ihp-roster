---
id: ir-vgdg
status: closed
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


## Notes

**2026-04-30T07:11:05Z**

Implemented initial relational version schema in Application/Schema.sql: staff_pay_versions, shift_type_pay_versions, export_job_entries, timesheet entry version ids, and Xero submission entry version ids. calculate_timesheet_pay now resolves approved entries from version ids instead of pay_config_snapshots.

**2026-04-30T07:28:58Z**

Implemented relational staff/shift pay version schema, export provenance table, Xero submission provenance ids, tenant integrity checks, and pay SQL resolution from approved entry version ids. Runtime snapshot table/column design replaced by append-only version rows.
