---
id: ir-yoho
status: closed
deps: [ir-nlv5]
links: []
created: 2026-06-15T23:44:59Z
type: feature
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:roster, launch]
---
# Add create trial staff controller flow

Add a manager-and-above flow for creating a current-venue trial staff placeholder without sending an invite or creating a user.

## Design

Add NewStaffAction/CreateStaffAction or an equivalent StaffController flow. Gate with ensureIsUser, ensureCurrentVenue, ensureProfileCompleted, ensureManagerRole, and ensureVenueWritable for creation. Reuse existing staff form/validation sections where practical. Render a full staff-details form prefilled with obvious placeholder values for required contact/emergency fields so the flow stays quick while satisfying current schema constraints. Create Staff with user_id NULL, current venue, active status, selected roster groups, and current admin-only pay-field rules where applicable. Validate/treat roster group ids as current-venue scoped.

## Acceptance Criteria

A manager can create a trial staff placeholder for the current venue. A non-manager cannot create one. Tampered or cross-venue roster group ids are rejected or rerendered safely. The created staff row has user_id NULL and active TRUE. Selected roster group assignments are persisted. Focused controller tests pass.


## Notes

**2026-06-15T23:55:48Z**

Implemented NewStaffAction/CreateStaffAction for current-venue trial placeholders, using existing staff form shape with placeholder contact defaults and current roster-group/pay-field validation. Focused StaffController Hspec and typecheck pass.
