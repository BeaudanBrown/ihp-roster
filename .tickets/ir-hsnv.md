---
id: ir-hsnv
status: closed
deps: [ir-2fvy]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 2
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, admin, shift-types, focus, frontend-surface]
---
# Migrate admin shift types to actor-local invalidation with focus protection

Convert shift type admin successful mutations to actor-local semantic invalidation while preserving focused-field protection.

## Design

Respect the declared focused-field protection policy and defer-until-blur behavior during refetch. Successful create/update/reorder/archive responses should not replace authoritative business rows via actor OOB; they should return extras plus actor-local invalidation. Validation failures may still rerender local form/section errors.

## Acceptance Criteria

Shift type create/update/reorder/archive success responses contain no business `hx-swap-oob` fragments. Actor-local invalidation refreshes the shift-types fragment through the runtime, including duplicate mounts. Focus-protection tests or coverage prove active field behavior is not regressed.

## Notes

**2026-07-07T04:54:16Z**

Migrated admin shift type successful HTMX mutations to actor-local semantic invalidation. Create/update/move now return HX-Reswap none plus the shared bepis:live-fragments-refresh trigger for admin-shift-types/admin-shift-types-fragment, with no rendered shift-type business fragment or Xero business OOB. Existing fragment GET remains the authoritative render path and the declared focused-field protection policy on adminShiftTypesFragment remains unchanged. Validation/error branches still use the existing section rerender helper. Verification: hspec-test --match 'serves shift type and roster group add/update through targeted admin fragments'; hspec-test --match 'shift type'.
