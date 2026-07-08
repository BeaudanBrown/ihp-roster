---
id: ir-tq31
status: closed
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [profile, leave-requests, staff, frontend-contracts, htmx]
---
# Migrate Leave/Profile/Staff request actions

Classify leave request, profile section, staff profile, passkey, and staff document HTMX controls. Migrate surface-owned collaborative/profile fragments to generated action contracts and keep auth/security/dialog-only flows global or full-page.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.


## Notes

**2026-07-08T02:09:17Z**

Migrated surface-owned Leave/Profile actions: manager leave archive pagination, approve/deny review actions, and profile self-service leave creation now render through generated FrontendSurface actions. Existing passkey and staff/profile dialog/form overlay flows were already migrated via OverlayAction. Remaining Staff edit leave form and roster self-service leave form are classified as non-surface/global helper-lane candidates because they target local form fragments outside a mounted Staff/Profile/LeaveRequests surface; leave for ir-4spc rather than forcing into SurfaceAction. typecheck, frontend-check, and focused Leave/Profile/Staff/Roster checks pass.
