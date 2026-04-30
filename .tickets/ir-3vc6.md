---
id: ir-3vc6
status: open
deps: []
links: [ir-lz0x, ir-caf4, ir-z5dj, ir-hw2v]
created: 2026-04-30T06:31:22Z
type: bug
priority: 1
assignee: beaudan
parent: ir-m8hc
tags: [area:payroll, area:schema, area:exports, source:2026-04-30-audit]
---
# Implement pay snapshot reproducibility for approved/exported payroll

Approved timesheet pay and exported payroll output must resolve rates, pay levels, shift labels, and relevant config from the immutable pay_config_snapshot rather than mutable current tables.

## Design

Close the gap identified in specs/06-pay-engine.md and plans/60-v1-schema-hardening.md. Update calculate_timesheet_pay / calculate_timesheet_pay_range and export helpers so pay_config_snapshot_id drives historical resolution whenever present. Keep draft/unapproved calculations on current config. Coordinate with ir-caf4 and ir-lz0x.

## Acceptance Criteria

Tests mutate shift type override/default award level/rates after approval and prove the approved entry and exports remain unchanged; mixed-snapshot exports still report their snapshot context; typecheck and focused payroll/export specs pass.


## Notes

**2026-04-30T06:57:13Z**

Design pivot: do not implement the JSON pay_config_snapshots remediation as originally written. Supersede this with ir-hw2v, which replaces JSON snapshots with append-only relational pay config versions and explicit approval/export/Xero locks.
