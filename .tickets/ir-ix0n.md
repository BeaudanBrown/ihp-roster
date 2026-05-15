---
id: ir-ix0n
status: closed
deps: []
links: []
created: 2026-05-15T02:26:59Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:architecture, typing]
---
# Introduce surface-indexed live surface types

Add typed wrappers and a surface contract so each live surface owns its key type, fragment type, scope construction, default fragments, fragment refs, render hook, request decoration, and wire conversion.

## Design

Build the new API as a compatibility layer over the existing JSON protocol and current LiveSurfaceConfig shape. Prefer local feature fragment enums and type-indexed FragmentRef/SurfaceScope wrappers so fragments cannot be broadcast on the wrong surface by accident.

## Acceptance Criteria

At least one small existing surface compiles through the typed API, existing live-update wire JSON remains compatible, and new code no longer needs to hand-assemble untyped surface config for that migrated surface.

