---
id: ir-3txn
status: open
deps: []
links: [ir-9jap]
created: 2026-07-09T02:39:01Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [agent-loop, area:payroll, area:fwc, venue:rooks]
---
# Apply award-rate updates from first full pay period

Ensure award reference data refreshes promptly and pay calculation applies new rates from the first full roster/timesheet week starting on or after the operative date.

## Design

V1 uses the roster/timesheet week as the pay-period proxy. New award rates must apply from the first full such week commencing on or after the operative date, matching Fair Work guidance for first full pay period commencing on or after 1 July. Future export/payroll-specific period definitions are out of scope. FWC MAPD refresh scheduling should be prompt enough not to miss annual updates.

## Acceptance Criteria

FWC MAPD refresh scheduling is documented and made prompt; pay calculation resolves ordinary, penalty, and applicable allowance rates against the timesheet week start; regression tests prove old rates apply to weeks crossing 1 July that started before 1 July and new rates apply to weeks starting on/after 1 July; docs record the V1 pay-period proxy and future limitation.

