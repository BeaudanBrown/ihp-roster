---
id: ir-dvoi
status: closed
deps: []
links: []
created: 2026-07-08T04:59:57Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, staff, profile, surface]
---
# Add StaffSurface and shared staff profile definitions

Add StaffSurface for manager/admin staff editing and migrate shared staff/profile sections to generated request metadata with shared definitions.

## Design

Keep ProfileSurface for current-user self-service and add StaffSurface for manager editing scoped by venue and target staff. Share staff/profile field bundles, action options, fragment-option aliases, renderers, and tests while keeping distinct surface scopes/fragments. Overlay/modal mode should be AppShell-dialog-backed after AppShell migration.

## Acceptance Criteria

Profile and Staff shared actions expose consistent field sets; shared renderer is used in both contexts; Profile self-service and manager staff edit tests pass; raw HTMX removed from shared staff/profile sections.


## Notes

**2026-07-08T05:49:29Z**

Added first-class StaffSurface alongside ProfileSurface with distinct staff fragment identities/scopes and shared profile/preference action field bundles. Migrated shared StaffProfileSections profile-fragment request mode from hand-authored HTMX attrs to generated FrontendSurface action rendering with an explicit custom HTMX marker for concrete section target/swap. Added consistency coverage for Profile/Staff action field sets and guardrails banning raw request HTMX in shared staff/profile sections. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-check; bash ./bin/in-env hspec-test --match "Frontend contract" --match "ProfilesController" --match "StaffController" --match "SurfaceGuard".
