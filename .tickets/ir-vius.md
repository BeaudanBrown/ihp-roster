---
id: ir-vius
status: open
deps: [ir-jau6]
links: []
created: 2026-05-22T06:01:53Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-it5h
tags: [agent-loop, area:live-fragments, area:architecture]
---
# Add server-side live-fragment containment paths

Add server-side fragment containment metadata and normalization to the typed live-surface pipeline.

## Design

Change SurfaceFragmentRef to carry the existing LiveUpdateWireFragment plus a server-only containment path. mkSurfaceFragmentRef defaults the path to [targetId]. Add a helper such as surfaceFragmentRefWithPath for surfaces that declare nesting. Normalize refs before actor refreshes, default resync fragments, and registry passive invalidation targets: preserve order, remove exact duplicate paths, and drop descendants when an ancestor path is present. Keep LiveUpdateWireFragment JSON unchanged.

## Acceptance Criteria

Unit tests cover duplicate paths, parent/child elimination, nested parent/child elimination, and sibling preservation. Existing live-update JSON shape remains unchanged. Focused LiveSurface and LiveUpdate tests pass.

