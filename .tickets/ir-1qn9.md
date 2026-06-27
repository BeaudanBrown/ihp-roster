---
id: ir-1qn9
status: closed
deps: [ir-zaug]
links: []
created: 2026-06-27T06:57:15Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-8476
tags: [agent-loop, live-surface]
---
# Add current-venue surface scope helpers

Add venue scope descriptors and current-venue unit/general surface helpers that safely parse wire venue scopes and apply explicit auth requirements.

## Acceptance Criteria

Helpers compile and tests cover accepted/rejected venue wire scopes and generated surface config defaults.


## Notes

**2026-06-27T07:06:02Z**

Added VenueLiveUpdateScope, venueLiveSurfaceDescriptorForVenue, currentVenueLiveSurfaceDescriptor, currentVenueUnitScopeSurface, and test-only/current-venue-for-venue helpers. Tests cover safe venue wire-scope acceptance/rejection, unit-scope config defaults, and keyed local scope preservation. Verification passed: typecheck and focused LiveSurface Hspec.
