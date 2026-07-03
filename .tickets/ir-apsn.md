---
id: ir-apsn
status: open
deps: [ir-28n8, ir-aosk]
links: []
created: 2026-07-03T11:15:32Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3b6m
tags: [agent-loop, surfaces, live-updates]
---
# Plan invalidations directly from active FrontendSurface subscriptions

Remove Web.LiveSurfaceRegistry planningInputForScope by planning against mounted fragments stored on active subscriptions.

## Design

For each active subscription, run the generated FrontendSurface dependency planner with the subscription scope and mounted fragments, convert selected mounted fragments to generated wire fragments, coalesce per subscriber/scope, and broadcast. Do not reconstruct candidate fragments from LiveUpdateScope constructors.

## Acceptance Criteria

Passive invalidation tests pass with subscriber-local mounted fragments. planningInputForScope and per-feature candidate reconstruction for passive planning are deleted. Dependency matching remains generated-data driven.

