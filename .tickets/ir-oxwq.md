---
id: ir-oxwq
status: closed
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


## Notes

**2026-07-07T03:36:31Z**

Implemented in one cleanup pass. Summary: added canonical FrontendSurface lazy fragment config/renderer with feature-owned root classes and generated UI-region attrs; wired roster staff panel slot classes; derived lazy load policy, trigger, and placeholder defaults from existing Lazy/Trigger/Placeholder options; deleted stale Application.Helper.View.LazySurface; updated all mounted fragment constructors/call sites; added Hspec/guardrail/docs coverage. Verification: typecheck, frontend-contracts-check, frontend-test, hspec-test --match FrontendSurface, hspec-test --match lazy, frontend-surface-compile-fail-check, frontend-surface-guardrails, and frontend-check passed. Note: attempted old command name surface-compile-fail-check, but project command is frontend-surface-compile-fail-check.
