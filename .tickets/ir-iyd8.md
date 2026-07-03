---
id: ir-iyd8
status: open
deps: [ir-dog6, ir-qjyh]
links: []
created: 2026-07-03T04:17:38Z
type: chore
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, docs, guardrails, surfaces]
---
# Document and guard final FrontendSurface transport architecture

## Design

Update FrontendSurface authoring docs and agent guidance to describe the final primitive set, Live fragment option, generated surface-native live transport, and removed legacy paths. Add guardrails against data-live-update-surface, handwritten surface mapping parsers, LiveSurfaceManifest, old feature-specific live DTO variants, and removed top-level primitives.

## Acceptance Criteria

Docs reflect the final architecture. Guardrails pass. Epic closeout notes document that no known stale compatibility layer remains.


## Notes

**2026-07-03T04:55:09Z**

User approved temporary bridge/pattern compatibility during incremental implementation only if final docs/guardrails include a thorough scan and purge proving no old bridge code remains.
