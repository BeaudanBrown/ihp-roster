---
id: ir-tngm
status: in_progress
deps: []
links: []
created: 2026-07-02T12:57:06Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, surfaces, live-fragments]
---
# Migrate remaining legacy live surfaces to FrontendSurface

Move all remaining legacy TypedLiveSurfaceDefinition/data-live-update-surface surfaces to type-level FrontendSurface specs and SurfaceImpl runtime mounts, then remove legacy authoring/runtime paths where no longer used.

## Design

Migrate in small batches: Leave Requests, Billing/Support, Profile surfaces, Admin simple surfaces, Admin Xero nested surface, then remove legacy LiveSurface registry/runtime/browser compatibility if no production code remains. Stop for design decisions around profile/admin-Xero scope modeling or final legacy runtime removal if compatibility tests require a protocol decision.

## Acceptance Criteria

No production feature surface uses TypedLiveSurfaceDefinition, data-live-update-surface, serveTypedLiveFragment, respondWithTypedLiveSurfaceFragments, or Web.LiveSurfaceRegistry catalog entries; generated contracts cover all surfaces; browser subscriptions and passive invalidation still work; focused Hspec/frontend/E2E checks pass.


## Notes

**2026-07-02T13:11:03Z**

Migrated Leave Requests list surface to FrontendSurface: added type-level spec/runtime bridge, rendered data-bepis-surface mounts, direct fragment/controller responses, registry auth/planning descriptor, generated TypeScript parser support, and updated tests. Verified typecheck, frontend-check, LeaveRequestsController, FrontendSurface-focused Hspec.
