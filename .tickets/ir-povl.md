---
id: ir-povl
status: closed
deps: [ir-o5og]
links: []
created: 2026-07-04T01:20:55Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-7jqj
tags: [agent-loop, surfaces, dependencies]
---
# Use generated dependency planner for all actor and passive fragment selection

Remove feature-local resource-to-fragment dependency mirror helpers and route actor affected-fragment selection through generated FrontendSurface DependsOn metadata.

## Design

Expose ergonomic generated-planner helpers for mounted fragments/wire fragments. Replace timesheets/roster/profile/billing/leave/support/admin *FragmentDependencies and *AffectedFragments mirrors with calls into Application.Helper.FrontendSurface.DependencyPlanner. Update or delete tests that assert duplicate manual dependency lists; replace with tests proving generated planner behavior and drift guardrails.

## Acceptance Criteria

No production feature-local dependency mirror helpers remain unless explicitly justified in the ticket notes; actor and passive invalidation use the same generated DependsOn planning path; LiveSurfaceDependency tests assert generated planner behavior; verification passes.

