---
id: ir-tq31
status: open
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

