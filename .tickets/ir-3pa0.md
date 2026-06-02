---
id: ir-3pa0
status: open
deps: [ir-ibrg]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, pay-items]
---
# Implement MYOB wage category matching and managed creation

Provide MYOB feature parity for local pay bucket to remote wage category mapping and managed wage category creation where safe.

## Design

Map provider-neutral pay item requirements to MYOB Wage payroll categories. Respect MYOB constraints such as 31-character names, hourly WageType, RegularRate or FixedHourly details, STP category defaults, account override behavior, RowVersion, and category assignment implications. Include deterministic short naming and local metadata to preserve auditability.

## Acceptance Criteria

MYOB can match existing wage categories and create required managed wage categories through the shared Payroll pay item flow. Name collisions, unsupported wage types, account issues, and API validation errors produce actionable blockers. Tests cover naming, payloads, matching, and raw response persistence.

