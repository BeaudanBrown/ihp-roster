---
id: ir-hw6a
status: in_progress
deps: [ir-9ykn]
links: []
created: 2026-06-28T12:23:42Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-r3wv
tags: [agent-loop, live-surfaces]
---
# Unify registered live surface catalogs

Reduce duplicated manifest/authorization/planning lists in Web.LiveSurfaceRegistry.

## Acceptance Criteria

Manifest, authorization, and planning derive from a single canonical registry catalog where possible; Hspec passes.


## Notes

**2026-06-28T12:35:37Z**

Refactored Web.LiveSurfaceRegistry to use a single RegisteredLiveSurfaceEntry catalog for manifest, authorization, request-context planning, and background planning derivation. Focused Hspec is blocked by pre-existing missing OpenTelemetry modules in Application/Helper/Telemetry.hs.
