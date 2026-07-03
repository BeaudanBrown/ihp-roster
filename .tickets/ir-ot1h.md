---
id: ir-ot1h
status: open
deps: [ir-kb9l]
links: []
created: 2026-07-03T02:45:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, frontend, surfaces, runtime]
---
# Implement nested surface runtime reconciliation

Make nested surface mounts lifecycle-safe when parent fragments are swapped or removed.

## Design

Track surface instances by surface + scopeKey + mountKey. Reconcile active instances against current DOM mounts after page ready, HTMX swaps/settle, and live fragment swaps. Dispose absent instances deepest-first, initialize new instances, and keep websocket subscriptions as the union of current DOM mounted surface scopes.

## Acceptance Criteria

Parent swap removing child/grandchild cleans subscriptions; replacing the same child instance does not duplicate subscriptions; replacing child scope unsubscribes old and subscribes new; newly inserted child mount initializes/resyncs; existing live-update behavior still works.

