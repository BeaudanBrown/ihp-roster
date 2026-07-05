---
id: ir-sxo2
status: open
deps: [ir-uvf9]
links: []
created: 2026-07-05T10:20:36Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-815h
tags: [frontend-contracts, typescript, surface]
---
# Rationalize generated FrontendSurface convenience aliases

Audit duplicated generated Surface vs FrontendSurface TypeScript shapes after the unified renderer.

## Design

Study Application.Helper.FrontendContract.TypeScript renderDerivedSurfaceWireTypes and renderFrontendSurfaceRuntime plus frontend/ts/live-updates and lazy-surface consumers. Decide which FrontendSurface* aliases are domain terminology/runtime APIs and which are compatibility duplication now that canonical SurfaceScope/SurfaceFragmentKey/SurfaceWireFragment/SurfaceSubscription exist. Prefer migrating runtime consumers to canonical generated live-update wire types where low-risk; retain mount-config and registry types that are genuinely surface runtime metadata. Document retained aliases with comments in the renderer.

## Acceptance Criteria

A short decision is recorded in code/docs. Any deleted aliases have frontend consumers migrated and frontend-check passes. Retained FrontendSurface* output is explicitly domain/runtime convenience, not a parallel contract authority.

