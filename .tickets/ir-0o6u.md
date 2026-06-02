---
id: ir-0o6u
status: open
deps: [ir-q5uu]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, area:schema]
---
# Add provider-neutral payroll reference and mapping tables

Generalise employees, pay items, accounts, periods/pay runs, staff mappings, and pay-bucket mappings away from Xero-specific tables.

## Design

Create provider-neutral reference tables for remote employees, pay items/wage categories, accounts, optional provider periods/pay runs/calendars, staff mappings, local bucket mappings, provider setup selections, sync runs, and raw payload snapshots. Use provider capabilities for optional concepts rather than forcing MYOB into Xero names.

## Acceptance Criteria

Generated types expose provider-neutral records. Existing Xero reference data can be migrated or backfilled into the new shape. Venue and connection integrity constraints prevent cross-venue/provider leakage. Query/read-model seams exist for downstream Payroll UI without importing Xero-specific table names.

