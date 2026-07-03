---
id: ir-4oed
status: closed
deps: [ir-zsrm]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, live-updates, codegen]
---
# Generate dependency planner from DependsOn declarations

Generate the live invalidation planner from explicit DependsOn declarations.

## Design

Planner follows the current fragment-dependencies model: for each active parsed scope and candidate mounted fragment, construct concrete dependency resource values from FromScope/FromFragment declarations, intersect with touched generated resource values, then coalesce/normalize selected fragments.

## Acceptance Criteria

Generated planner reproduces current Timesheets, Roster, Profile, Billing, Support, Leave Requests, and Admin invalidation behavior. Web.LiveSurfaceRegistry.planSurfaceInvalidation feature case list is removed/replaced. No resource dependency inference or fanout primitive is introduced in V1.


## Notes

**2026-07-03T08:13:43Z**

Generated planner now evaluates FrontendSurface DependsOn declarations generically against generated resource values; Web.LiveSurfaceRegistry only supplies mounted-fragment candidates and wire conversion.
