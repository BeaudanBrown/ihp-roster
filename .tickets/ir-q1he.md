---
id: ir-q1he
status: open
deps: [ir-2mlj]
links: []
created: 2026-05-21T07:00:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-uir5
tags: [agent-loop, area:performance, area:roster, area:live-fragments]
---
# Prototype one low-risk resource-versioned cached loader

Implement a minimal process-local prototype for one safe shared read loader if the design ticket confirms the API is viable.

## Design

Choose one low-risk loader from the design, preferably current venue shift types, current venue roster groups, or ordered roster week slot definitions. Use explicit typed inputs and dependency versions; do not cache user-scoped values. Keep the prototype small and reversible. Integrate only at one or two call sites needed to measure behavior, not across the app. Add cache stats/profiling detail by loader name if practical. The prototype must not change user-visible behavior or projection semantics.

## Acceptance Criteria

One selected loader can return from the process-local cache using a versioned key and miss after a relevant resource mutation. Tenant isolation is covered. Stale-data regression coverage demonstrates an update/reorder/archive of the underlying resource is visible after mutation. Profiling or logs expose enough hit/miss/load data to compare with direct DB reads. If the design concludes no safe prototype should be implemented yet, this ticket records that decision and closes without code.

