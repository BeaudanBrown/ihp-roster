---
id: ir-lz0x
status: closed
deps: []
links: [ir-caf4, ir-3vc6, ir-hw2v, ir-z5dj]
created: 2026-04-29T04:41:30Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-caf4
tags: [area:schema, source:plans-60]
---
# Add snapshot reproducibility foundation

Make pay/export snapshots reproducible enough for audit and later Xero submission.


## Notes

**2026-04-30T06:57:18Z**

Design pivot: snapshot reproducibility foundation should no longer be implemented with pay_config_snapshots JSONB. Use ir-hw2v for append-only relational pay config versions, then remove the JSON snapshot system.

**2026-04-30T07:29:20Z**

Superseded by ir-hw2v. Snapshot foundation remains audit/problem context only; current implementation uses staff_pay_versions, shift_type_pay_versions, export_job_entries, and Xero submission provenance rows.
