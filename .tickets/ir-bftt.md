---
id: ir-bftt
status: open
deps: [ir-u1hq]
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-3txn
tags: [agent-loop, payroll, sql]
---
# Resolve award rates by timesheet-week start

Update pay calculation so award operative dates are evaluated against the timesheet week start for V1.

## Design

Find the canonical SQL/pay calculation paths for base rates, penalty rates, and time-allowance rates. Thread or derive the venue timesheet week start for each entry and use that date for award operative_from/operative_to lookups instead of using the individual worked_on date where that would split a week crossing 1 July.

## Acceptance Criteria

Pay calculation uses the roster/timesheet week start as the V1 pay-period effective date for award-rate lookup. Existing approved/pay-version behavior remains compatible. Typecheck and focused pay tests pass.

