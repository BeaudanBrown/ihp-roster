---
id: ir-b1lx
status: closed
deps: [ir-6bfl]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 3
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, roster, leave, self-service]
---
# Unify roster self-service leave actor refreshes

Bring the roster staff self-service leave form into the same successful actor response pattern.

## Design

Identify whether the roster self-service panel should own a separate fragment or reuse an existing profile/leave fragment; update successful leave submit/error responses consistently without disturbing roster live invalidation.

## Acceptance Criteria

Roster leave submit success uses a declared fragment renderer plus toast; validation failures remain scoped; mobile roster self-service coverage still passes or is added.


## Notes

**2026-06-30T01:52:46Z**

Implemented with the same non-cached typed fragment model convention. Added Web.RosterWeeks.StaffSelfServiceLeaveFragments with a closed RosterStaffSelfServiceLeaveFragment ADT, default form model builder, FragmentPlain/FragmentOob renderer, and response helper. Roster leave success now returns the declared roster-staff-self-service-leave-form-fragment as OOB plus toast and sets HX-Reswap=none so the existing validation target remains direct/outerHTML for failures. Removed the controller-local default roster leave builder duplication. Added focused controller coverage for roster self-service success response shape. Verification passed: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LeaveRequests'.
