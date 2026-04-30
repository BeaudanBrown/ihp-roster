---
id: ir-d1po
status: open
deps: []
links: []
created: 2026-04-30T06:56:59Z
type: task
priority: 1
assignee: beaudan
parent: ir-hw2v
tags: [area:payroll, area:schema, area:cleanup]
---
# Remove pay_config_snapshots JSON system

Remove the JSON snapshot system after relational versioning and locks replace it.

## Design

Drop pay_config_snapshots and pay_config_snapshot_id references from Schema.sql, generated types, helpers, exports, Xero readiness/preview/submission, tests, fixtures, profile seed, and specs/AGENTS docs. Replace snapshot labels in exports with relational version manifest/version labels.

## Acceptance Criteria

No app-runtime references to pay_config_snapshots, pay_config_snapshot_id, or payConfigSnapshotId remain except historical migration notes; schema has no pay_config_snapshots table; typecheck and focused payroll/export/Xero tests pass.

