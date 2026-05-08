---
id: ir-nimj
status: closed
deps: [ir-bub1, ir-knps]
links: []
created: 2026-05-08T00:01:17Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:auth, area:security]
---
# Add manual venue read-only enforcement

Implement the write-gating code path for manually disabled billing venues while keeping read access and payment recovery available.

## Design

Centralize write checks in a helper such as ensureVenueWritable and apply it to venue-scoped mutating controllers/jobs. Allowed paths include login, read views, user profile/security, billing Checkout/Portal, and super-admin support controls. Block roster, timesheet, unavailability, admin, Xero mutation/sync, import, and bulk-change writes.

## Acceptance Criteria

A super-admin manual read-only toggle makes the venue effectively read-only for ordinary users and venue roles while preserving billing recovery paths. Focused tests prove representative mutating routes are blocked and allowed routes still work.

