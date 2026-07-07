---
id: ir-oxwq
status: open
deps: [ir-u6dp]
links: []
created: 2026-07-07T03:24:30Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, cleanup]
---
# Delete stale LazySurface helper after consolidation

Remove the unused Application.Helper.View.LazySurface abstraction after the canonical FrontendSurface lazy path owns equivalent placeholder/chrome behavior.

## Design

Move any useful skeleton/chrome rendering from Application.Helper.View.LazySurface into the canonical FrontendSurface lazy runtime/helper path, or replace it with simpler local canonical helpers. Delete Application/Helper/View/LazySurface.hs, remove its re-export from Application/Helper/View.hs, and remove its SurfaceGuard allowlist entry if no longer needed.

## Acceptance Criteria

rg Application.Helper.View.LazySurface finds no production/test imports except deleted history. Application/Helper/View/LazySurface.hs is gone. Shared lazy CSS remains only if still used by canonical placeholders. No stale duplicate Haskell lazy abstraction remains.

