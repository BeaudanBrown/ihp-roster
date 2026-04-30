---
id: ir-srwi
status: closed
deps: []
links: []
created: 2026-04-30T06:56:38Z
type: task
priority: 1
assignee: beaudan
parent: ir-hw2v
tags: [area:payroll, area:schema]
---
# Implement relational pay config versions and calculation resolution

Add append-only pay config version tables and make pay calculation resolve approved entries from version ids.

## Design

Migrate timesheet_entries from pay_config_snapshot_id to explicit version references such as shift_type_pay_version_id and staff_pay_version_id. Draft entries may resolve current active versions; approved entries must resolve only stored version ids. calculate_timesheet_pay/range should stop reading pay_config_snapshots JSON.

## Acceptance Criteria

Schema/types regenerated; pay SQL and helpers use relational version ids; tests mutate current pay config by creating newer versions and prove approved entry pay result remains stable.


## Notes

**2026-04-30T07:28:59Z**

Implemented approval-time staff_pay_version_id and shift_type_pay_version_id binding, helper orchestration, pay result decoding, profile seed/test fixture conversion, and calculate_timesheet_pay relational resolution. regen-types, typecheck, and focused Pay/Payroll/Exports/Xero specs pass.
