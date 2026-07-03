---
id: ir-zsrm
status: open
deps: [ir-4oed]
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

Every current Live fragment has explicit dependency or resync declarations. Generated planner matches existing focused Hspec expectations. No current live resource remains outside generated declarations.

