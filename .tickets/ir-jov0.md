---
id: ir-jov0
status: open
deps: [ir-mwco, ir-2r0g]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, readiness]
---
# Implement MYOB readiness duplicate and processed-entry blockers

Add MYOB-specific readiness checks behind the provider-neutral blocker shape.

## Design

Validate active connection, OAuth/token health, company-file credential state, latest reference sync, staff mappings, pay item mappings/managed requirements, employee wage-category assignment, approved source entries, period support, existing remote timesheets, and Processed entries. Define create/update/block behavior for MYOB Timesheet PUT semantics.

## Acceptance Criteria

Shared Payroll preparation can show MYOB blockers and warnings without MYOB-specific UI logic. Existing/processed remote entries block silent mutation. Missing credentials, mappings, assignments, and stale references are actionable. Tests cover representative blocker combinations.

