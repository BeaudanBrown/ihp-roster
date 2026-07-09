---
id: ir-v0ts
status: open
deps: [ir-e41r]
links: []
created: 2026-07-09T01:05:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, live-fragments]
---
# Add resource-driven actor live refresh helper

Make actor-local live refresh selection use the same semantic dependency planning as passive invalidation.

## Design

Add a helper such as setActorLiveResourcesRefresh scope touchedResources mountedFragments, or an equivalent API. Reuse the existing dependency planner so actor refresh and passive websocket invalidation agree. Cover static and parameterized fragments. New migrated success paths should select resources, not DOM target ids.

## Acceptance Criteria

New helper exists and is documented. Tests prove touched resources resolve only matching mounted fragments. Actor and passive planning agree for static and parameterized fragments. No successful actor business OOB HTML is introduced.

