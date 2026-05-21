---
id: ir-7tkw
status: open
deps: [ir-q1he]
links: []
created: 2026-05-21T07:00:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-uir5
tags: [agent-loop, area:performance, area:architecture]
---
# Measure prototype and decide projection decomposition path

Use the prototype and existing profiling to decide whether granular read caching should expand, remain limited, or replace any projection responsibilities later.

## Design

Compare query count, request timing, cache hit/miss/load behavior, and implementation complexity for current projection-backed roster/timesheet/leave paths versus the prototype loader. Evaluate whether component caches reduce viewerKey pressure or simply add complexity. Produce a recommendation: keep projection snapshots as-is, add selected component caches, introduce resource-level versions first, or open a new explicit projection-decomposition epic. Include a rollback/removal recommendation if the prototype does not justify itself.

## Acceptance Criteria

A documented decision summarizes measurements, tradeoffs, risks, and next steps. It states whether to expand granular caching and names any follow-up tickets needed. It explicitly does not silently decompose roster/timesheet/leave projections in this ticket. Existing typecheck and relevant focused tests pass after any prototype code.

