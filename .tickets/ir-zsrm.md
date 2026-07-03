---
id: ir-zsrm
status: closed
deps: [ir-ai98]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, surfaces, live-updates]
---
# Migrate current live resources to FrontendSurface declarations

Add Resource and explicit DependsOn/ResyncOnly declarations for all current live surfaces and fragments.

## Design

Migrate Timesheets, Roster, Leave Requests, Billing, Support, Profile, and Admin venue config/settings/invites/exports/shift types/roster groups/Xero resources. If any dependency cannot be expressed with Resource/DependsOn/FromScope/FromFragment/ResyncOnly, pause and ask for design clarification instead of keeping a final custom hook.

## Acceptance Criteria

Every current Live fragment has explicit dependency or resync declarations. Declarations cover the current planner behavior and are ready for the generated planner to consume. No current live resource remains outside generated declarations.


## Notes

**2026-07-03T07:16:17Z**

ir-qhzl marked current Live fragments ResyncOnly as a validation placeholder. Replace ResyncOnly with explicit Resource/DependsOn declarations during current-resource migration except where a fragment is genuinely resync-only.

**2026-07-03T08:04:03Z**

Migrated direct planner dependencies from ResyncOnly placeholders into explicit FrontendSurface DependsOn declarations. Expansion-only resources such as StaffRosterMembership and StaffPayProfile still feed existing expansion before planner consumption.
