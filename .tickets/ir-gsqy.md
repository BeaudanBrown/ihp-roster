---
id: ir-gsqy
status: open
deps: [ir-0o6u]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, area:schema, area:pay]
---
# Generalise imported pay item overrides and pay snapshots

Replace downstream imported_xero_pay_item_id coupling with provider-neutral imported pay item references while preserving payroll reproducibility.

## Design

Update staff, shift types, staff pay versions, shift type pay versions, pay helper logic, payroll SQL/read models, and integrity triggers so custom provider pay item overrides can point to Xero earnings rates or MYOB wage categories through the same abstraction.

## Acceptance Criteria

Approved/exported payroll remains reproducible. Existing Xero custom pay item override behavior is preserved through migration. New provider-neutral override fields enforce venue/provider integrity and future MYOB wage-category overrides can reuse the same path without adding MYOB-specific columns.

