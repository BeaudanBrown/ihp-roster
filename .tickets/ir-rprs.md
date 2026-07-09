---
id: ir-rprs
status: open
deps: []
links: []
created: 2026-07-09T01:05:25Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, inventory]
---
# Inventory parameterized FrontendSurface migration candidates

Build the exact migration map across registered FrontendSurface surfaces before framework changes.

## Design

Inspect every registered surface: SurfaceLab, Timesheets, Roster, LeaveRequests, Billing, Support, Profile, Staff, and Admin surfaces. Classify each fragment family as already parameterized, duplicated and suitable for parameterization, single/static non-applicable, legacy/OOB special case, or decision point requiring user input. Record the migration table in ticket notes or living docs. Pause and ask before making ambiguous calls.

## Acceptance Criteria

Every registered surface is classified. Every applicable migration target is listed. Non-applicable surfaces/fragments have rationale. Ambiguities are marked as pause/ask-user decisions.

