---
id: ir-z9cg
status: closed
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [admin, frontend-contracts, htmx]
---
# Migrate Admin config request actions

Admin Shift Types, Venue Settings, Exports, Invites, and Xero admin request initiators currently use handwritten HTMX helpers/attrs. Migrate surface-owned controls to generated action contracts and leave dialog/global flows classified separately.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.


## Notes

**2026-07-07T08:30:04Z**

Migrated Admin Shift Types create/update forms, move buttons, and inactive toggle to generated FrontendSurface action contracts. Autosave attrs on embedded input/select/toggle controls remain handwritten pending a generic arbitrary-control/action-attrs helper or shared AppToggle integration decision.

**2026-07-07T08:59:37Z**

Added reusable applyFrontendSurfaceActionAttrs helper for generated action attrs on arbitrary controls. Migrated Shift Type name/pay-rate/colour autosave controls to generated actions with explicit CustomHtmx for HTMX extended trigger/include strings; active toggle still needs shared AppToggle integration.

**2026-07-07T09:08:06Z**

Migrated Admin Venue Settings, Invites, and Exports request initiators to generated FrontendSurface actions. Fixed the venue settings fragment marker/target mismatch by using AdminVenueSettingsFragment so generated hx-target matches the mounted DOM id.

**2026-07-07T09:08:45Z**

Next decision point: Admin Xero still has substantial HTMX. Some controls are in-surface AdminXero mutations (reference sync, calendar/account-code selections, pay item creation/archive, staff mappings/suggestions) and can migrate. The Xero timesheet preparation and pay-item import modal flows target the global dialog overlay and look like workflow/dialog controls rather than AdminXero surface actions; need decide whether to model them as AdminXero actions, a separate dialog workflow surface, or the global HTMX helper lane.

**2026-07-08T01:16:33Z**

Revised Admin Xero plan after OverlayAction migration: overlay/dialog flows are now out of scope for this ticket and handled by ir-od63/ir-1347. Remaining ir-z9cg scope is AdminXero surface-owned request initiators only: reference-data sync; payroll-calendar selection; pay-item account-code selection; create missing Xero pay items; archive imported pay item; staff mapping saves; staff mapping suggestion/apply controls; and any other Admin Xero page mutations targeting Admin Xero fragments. Keep pure fragment reads/lazy refreshes, shell/container navigation, and response OOB/toast/dialog cleanup out of SurfaceAction. Successful migrated mutations must continue actor-local/passive invalidation, not authoritative business OOB HTML.

**2026-07-08T01:36:39Z**

Completed remaining Admin config request-action rollout. Added generated AdminXero surface actions for reference sync, payroll-calendar and pay-item account-code selections, managed pay-item creation/archive, and staff mapping save/suggest controls. Added reusable FrontendSurface action attr-pair rendering so shared AppToggle inputs can carry generated action metadata; migrated Shift Type active autosave toggle through it. Verified typecheck, frontend-check, and focused AdminController/Xero hspec.
