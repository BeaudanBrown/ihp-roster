---
id: ir-hw2v
status: closed
deps: []
links: [ir-lz0x, ir-z5dj, ir-3vc6]
created: 2026-04-30T06:56:25Z
type: epic
priority: 1
assignee: beaudan
parent: ir-caf4
tags: [area:payroll, area:schema, area:exports, area:xero, source:design-pivot]
---
# Replace JSON pay snapshots with append-only pay config versions

Replace pay_config_snapshots JSONB as the operational reproducibility mechanism with append-only relational pay config version rows and explicit approval/export/Xero locks.

## Design

Implementation is complete; use `docs/workstreams/pay-config-versioning.md` as the transition record and living subsystem docs for current behavior. `docs/archive/plans/68-append-only-pay-config-versioning.md` is historical design context. Historical payroll must be reproduced from immutable relational version ids, not copied JSON snapshots.

## Acceptance Criteria

Approved timesheets, payroll exports, and Xero submissions reference immutable version rows; mutable pay-relevant edit actions create new versions instead of updating locked facts; JSON pay_config_snapshots are removed from schema/code/tests/specs; focused payroll/export/Xero tests prove old output remains stable after new versions are created.


## Notes

**2026-04-30T07:29:20Z**

Completed child implementation: relational pay version schema/resolution, admin version creation, approval/export/Xero provenance locks, JSON snapshot removal, docs updates, regen-types, typecheck, focused Pay/Payroll/Exports/Xero specs.
