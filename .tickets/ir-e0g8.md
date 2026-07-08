---
id: ir-e0g8
status: open
deps: []
links: []
created: 2026-07-08T04:59:57Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, htmx, architecture]
---
# Consolidate generated HTMX request metadata

Create one shared generated HTMX request metadata model instead of duplicating method/swap/target/trigger/include/sync/confirm/push-url/custom handling across request primitives.

## Design

Add a shared HTMX request metadata IR/value model and shared Haskell rendering helpers. Surface actions should lower into this model. AppShell actions will use it from the start. Namespaced type-level constructors may remain where useful, but they should lower to the same IR and TypeScript manifest shape where practical.

## Acceptance Criteria

Surface action rendering still passes; shared model covers method, target, swap, trigger, include, sync, confirm, push-url, and custom HTMX; tests cover Surface parity before/after deduplication.

