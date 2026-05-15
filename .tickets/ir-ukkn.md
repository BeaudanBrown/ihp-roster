---
id: ir-ukkn
status: closed
deps: [ir-ix0n]
links: []
created: 2026-05-15T02:27:27Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:architecture, area:operations]
---
# Introduce LiveBus abstraction for live updates

Hide the in-memory subscription and version store behind an interface so the live-update system has a clean path to multiple web processes or background job invalidations.

## Design

Keep the current in-process implementation as the default. Define the LiveBus boundary for register, unregister, active scopes, current version, increment version, and broadcast. Document future Postgres LISTEN/NOTIFY or Redis implementations without implementing them unless needed.

## Acceptance Criteria

Existing behavior is unchanged on a single process, tests can exercise the bus without unsafe global state leakage, and adding a distributed implementation later does not require rewriting controllers or surface definitions.

