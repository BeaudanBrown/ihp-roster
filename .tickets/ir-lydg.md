---
id: ir-lydg
status: open
deps: [ir-asoq]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Reconcile final Bepis docs and archive superseded plan

Move durable rules into local docs and mark the earlier component-pipeline workstream superseded by the final runtime facts architecture.

## Design

Update docs/architecture, Web/Controller/AGENTS, LiveUpdate spec, Audit docs if present, and workstream tracking. Archive or supersede legacy/transitional wording. Use “facts” and “telemetry boundary” language rather than manual evidence threading.

## Acceptance Criteria

Docs describe only the final no-legacy architecture, the fact-emitting helper rule, the single root type, the telemetry boundary, and accepted scanner/gate boundaries.
