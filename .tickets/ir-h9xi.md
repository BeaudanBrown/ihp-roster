---
id: ir-h9xi
status: closed
deps: [ir-9yr7]
links: []
created: 2026-07-08T09:28:50Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:admin, area:staff, area:payroll, agent-loop]
---
# Fix pay-rate dropdown labels to use venue-effective resolution

Replace stale current-rate label behavior in Admin shift type and Staff pay-rate dropdowns.

## Design

Stop treating all operative_to NULL rows ordered by createdAt as current. Update shared award-level option label rendering and controller read models to select the rate applicable today under the venue week-start rollover rule.

## Acceptance Criteria

Admin shift type and Staff create/edit dropdowns show the old rate before the rollover boundary and the new rate from the boundary; coverage includes duplicated open-ended rows from consecutive FWC refreshes.

