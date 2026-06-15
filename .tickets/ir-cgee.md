---
id: ir-cgee
status: open
deps: [ir-nlv5]
links: []
created: 2026-06-15T23:44:59Z
type: task
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:xero, area:timesheets, launch]
---
# Audit Xero payroll export eligibility for trial staff

Audit Xero, payroll readiness, mapping, and export staff queries so trial staff are not treated as payroll-eligible.

## Design

Inspect staff queries in Xero/payroll readiness, staff mappings, pay-scope derivation, and export/read-model paths. Use linked active staff helpers for eligibility. Preserve historical export behavior that resolves staff by existing timesheet entry ids; V1 prevents trial staff from entering timesheets, so historical lookup should not be over-filtered if it is only resolving already-created records. Add focused tests where behavior changes.

## Acceptance Criteria

Xero/payroll readiness does not require mappings or pay readiness for trial staff. Payroll-adjacent candidate staff queries use linked active staff unless resolving historical rows from timesheet entries. Historical exports still resolve staff attached to existing entries. Typecheck and focused Hspec pass.

