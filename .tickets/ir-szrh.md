---
id: ir-szrh
status: closed
deps: [ir-1qn9]
links: []
created: 2026-06-27T06:57:15Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-8476
tags: [agent-loop, live-surface]
---
# Migrate simple surfaces to refined helpers

Use fragment builders and current-venue helpers in simple admin/support/billing surfaces where appropriate.

## Acceptance Criteria

Simple descriptor-backed surfaces use refined helpers; behavior and generated contracts stay stable; focused tests pass.


## Notes

**2026-06-27T07:12:08Z**

Migrated simple surfaces onto refined helpers: admin exports, venue settings, roster groups, shift types now use current-venue helpers; support and billing use static fragment descriptors; admin invites uses venueLiveSurfaceDescriptorForVenue. Routes, auth, resources, query params, and focused protection remain explicit. Verification passed: typecheck, frontend-contracts-check, focused LiveSurface/registry Hspec.
