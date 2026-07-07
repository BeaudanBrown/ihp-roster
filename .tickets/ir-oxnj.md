---
id: ir-oxnj
status: closed
deps: [ir-rfyw]
links: []
created: 2026-05-29T03:16:09Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, xero, admin, live-fragments, frontend-surface]
---
# Migrate Admin Xero nested fragments to actor-local invalidation

Use Admin Xero as the proof surface for the new successful actor response model: semantic actor-local invalidation plus extras, not authoritative business OOB HTML.

## Design

Admin Xero has shell, staff mappings, pay items, and timesheets fragments. Existing `setAdminXeroActorRefresh` behavior is a useful precursor but must move behind the shared actor-local semantic invalidation helper and duplicate-mount-safe browser resolution. Successful mutations should return toasts/dialog clears/loading extras only; staff mappings, pay items, timesheets, and shell business HTML should refresh through fragment GET/refetch after actor-local and websocket invalidations. Containment still matters for selecting/normalizing fragments, but not for composing business OOB response HTML.

## Acceptance Criteria

Xero successful actor responses contain no authoritative business `hx-swap-oob` shell/child fragments. The shared actor-local invalidation helper replaces feature-specific payload construction. Duplicate mounts of Admin Xero refresh correctly in the actor tab. Dialog/toast extras remain. Existing Xero controller specs and contract tests are updated and pass.

## Notes

**2026-07-07T04:35:49Z**

Closeout: Admin Xero actor response migration complete for current child scope. Shared helper emits scopeKey-aware actor-local invalidation; duplicate mount runtime is covered by ir-rfyw. Reference sync HTMX responses, mapping/account-code/calendar successes, pay-item create/import/archive responses, staff mapping responses, and timesheet panel mutation responses now return semantic actor invalidation plus extras rather than business OOB. Plain Xero fragment GETs remain authoritative target-node HTML. Deferred known exception: renderCurrentVenueXeroSectionFragmentOob is still used from admin shift-type refresh and belongs to ir-hsnv/admin simple migration, not Admin Xero controller success paths. Verification recorded on child tickets: LiveUpdate runtime tests, frontend-check, SurfaceDependency Xero planning, focused Xero reference/pay-item/staff-mapping specs.
