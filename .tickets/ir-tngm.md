---
id: ir-tngm
status: closed
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

**2026-07-02T13:29:34Z**

Migrated Billing and Support to FrontendSurface: added type-level specs/runtime bridges, rendered data-bepis mounts, removed Web/Billing/LiveUpdates legacy definition, rewired fragment endpoints without serveTypedLiveFragment, moved registry auth/planning/descriptors to FrontendSurface helpers, updated parser/tests. Verified typecheck, frontend-check, BillingController, SupportController, LiveUpdate runtime, dependency specs.

**2026-07-02T13:30:53Z**

Paused at profile/admin remainder decision point after migrating Leave Requests, Billing, and Support. Remaining production legacy surfaces are Profile content/profile leave and Admin config/Xero surfaces. Profile content currently has one DOM target but multiple semantic fragments/section URLs; existing passive planning can invalidate non-open sections into the shared target. Need confirm whether FrontendSurface migration should preserve that exact behavior first or narrow passive profile content updates to the currently mounted/open section.

**2026-07-02T14:08:12Z**

Decomposed Profile content into section-level swappable accordion fragments (details, preferences, security, leave, RSA) and migrated Profile subscription metadata to FrontendSurface. Removed Profile TypedLiveSurfaceDefinition/data-live-update-surface/serveTypedLiveFragment usage; Profile fragment endpoints now render direct section/leave content responses. Passive profile invalidation now targets section DOM owners rather than the former whole profile-content fragment. Verified typecheck, frontend-contracts/frontend-check, ProfilesController, Live surface registry, and dependency specs.

**2026-07-02T14:09:34Z**

Completed requested Profile decomposition before migration. Remaining legacy surfaces are Admin settings/invites/exports/shift-types/roster-groups and Admin Xero. Next decision point is Admin Xero: legacy planning has a broad shell fragment plus nested staff-mappings/pay-items/timesheets fragments, so some Xero resource changes can invalidate both parent shell and child section. Need decide whether to preserve that overlapping behavior for migration or decompose shell/nested ownership to avoid double swaps.

**2026-07-02T21:33:18Z**

Added reusable FrontendSurface focused-field protection metadata. Mount JSON can now carry activeSelector/fieldKeyAttr/fieldNameFallback/containerSelector; the FrontendSurface TS compatibility parser translates it to the generated focused_field LiveFragmentProtection wire shape. Existing runtime bridges handle the richer variant, with focused tests in frontend and Hspec. This preserves the path needed for Admin Shift Types migration without bespoke surface logic.

**2026-07-03T00:09:44Z**

Cut Admin simple surfaces and Xero page fragments over to FrontendSurface mounts and direct fragment endpoints. Xero modal/dialog lane remains separate: FrontendSurface invalidations target page-owned admin-xero/xero-* fragments only, not dialog-overlay-mount. Typecheck and frontend-check pass. Focused Admin/registry Hspec now fails only on legacy expectations that still assert old typed/data-live-surface behavior and old Xero shell co-invalidation semantics; tests need updating to the new FrontendSurface/admin-Xero section behavior before closeout.

**2026-07-03T00:40:13Z**

Finished Admin surface migration follow-up: Admin venue settings, invites, exports, shift types, roster groups, and Xero now mount through FrontendSurface. Web.LiveSurfaceRegistry no longer uses the legacy typed-surface catalog for production planning/authorization/manifests; it plans all production surfaces through FrontendSurface helper seams. Xero actor-local refresh now uses Admin FrontendSurface fragments while keeping modal/dialog content in the dialog lane. Verified frontend-surface-guardrails, frontend-check, typecheck, and focused Admin/Xero/registry/guard Hspec.
