---
id: ir-7j0h
status: closed
deps: [ir-rfyw, ir-3y9k]
links: []
created: 2026-07-07T04:09:19Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, leave, billing, support, frontend-surface]
---
# Migrate remaining simple FrontendSurface success paths

Finish non-roster/non-admin/non-profile registered FrontendSurface success response migrations and document intentional exceptions.

## Design

Migrate or classify Leave Requests, Billing, Support, and lab paths. Profile has its own focused ticket (`ir-3y9k`) and should be referenced rather than duplicated here. Keep validation-local form/dialog responses direct. Keep billing/support/lab routes that are pure fragment GET, non-mutating, or test-only as documented exceptions rather than forcing fake actor invalidation.

## Acceptance Criteria

Leave successful mutations use actor-local invalidation where they update migrated FrontendSurface business UI. Billing/support/lab paths are migrated or explicitly documented as non-mutating/refetch-only/test-only exceptions. Success responses contain no migrated business OOB HTML. Focused specs pass.

## Notes

**2026-07-07T05:00:01Z**

Migrated remaining simple migrated FrontendSurface success responses for Leave Requests. Leave page manager approve/deny responses now actor-invalidate leave-requests-content via leaveRequestsSurfaceScope and return only dialog-clear/toast extras. Profile leave self-service create responses now actor-invalidate the parent profile leave section via profileSurfaceScope/profile-leave-section and return only toast extras; no profile leave business OOB is returned. Validation/no-staff errors remain direct-rendered local form responses. Roster responseContext remains direct roster self-service fragment until the roster migration chain owns it. Staff responseContext remains a non-FrontendSurface staff-admin local fragment response. Billing is classified as redirect/webhook/passive-fragment only for this epic: customer/control mutations redirect or webhook-broadcast billing resources, and ShowbillingStatusLiveFragmentAction remains the plain refetch endpoint. Support award/public-holiday sections are founder support fragments with passive invalidation and direct admin action responses outside migrated actor success scope; Surface Lab actions are support-only/test-lab direct HTMX action demos and intentionally not migrated. Verification: hspec-test --match 'LeaveRequestsController'.
