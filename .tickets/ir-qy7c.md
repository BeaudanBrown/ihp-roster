---
id: ir-qy7c
status: open
deps: [ir-9yr7]
links: []
created: 2026-07-08T09:28:50Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:payroll, area:schema, agent-loop]
---
# Apply venue-effective resolution to canonical pay calculation

Update PostgreSQL canonical pay calculation to choose award rates by venue-effective date instead of raw/open-ended row assumptions.

## Design

Update Application/Schema.sql and matching migration SQL for calculate_timesheet_pay/calculate_timesheet_pay_range. Preserve the existing approved-entry stability rule: approved entries must not pick rates created after approval and must continue to honor stored staff/shift pay-version ids.

## Acceptance Criteria

Pay tests prove a worked date before the next venue week uses the old rate, a worked date from the next venue week uses the new rate, and an approved entry remains unchanged after a newer rate import.

