---
id: ir-z9cg
status: in_progress
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
