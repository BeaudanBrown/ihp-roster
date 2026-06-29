---
id: ir-ka82
status: closed
deps: [ir-6q3e]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 1
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, research, confirmation]
---
# Confirm leave/profile fragment boundaries before migration

Research current leave/profile/roster self-service update paths and confirm the fragment boundaries before implementation.

## Design

Inspect Web.LeaveRequests.Projection, Web.Controller.LeaveRequests, Web.LeaveRequests.ProfileSelfService, Web.Profiles.LiveUpdates, profile view fragments, and roster self-service leave fragment usage. Ask whether profile leave form/list should be one surface or two if unclear after inspection.

## Acceptance Criteria

Ticket note records chosen fragment enum(s), target ids, validation-failure exceptions, and any changes caused by the foundation helper; no production behavior changes are made.


## Notes

**2026-06-29T23:54:03Z**

Boundary confirmation complete. Manager leave: canonical surface remains leave-requests with scope LeaveRequestsScope{venueId}; keep only LeaveRequestsProjectionContent as the live/actor fragment, target id leave-requests-content, GET ShowLeaveRequestsContentFragmentAction. LeaveRequestsProjectionPage/buildLeaveRequestsPageFragmentRef are obsolete page-shell compatibility and should be removed in ir-awhg; the page action should keep rendering the shell from the projection but not register a page live fragment. Validation failures are not part of this manager review path; approve/deny/create successes should use respondWithTypedLiveSurfaceFragments over LeaveRequestsProjectionContent plus dialog clear/toast extras. Archive pagination is a local non-mutation subfragment exception: leave-archive-page-content may continue to be served by swapOob=true until a later cleanup because it is not the successful actor-refresh path. Profile leave: use one nested profile-leave-requests surface, ProfileLeaveRequestsLiveFragment, target profile-leave-requests-content, GET ShowProfileLeaveRequestsContentFragmentAction, depending on StaffLeaveRequestsResource. It intentionally contains both profile-leave-request-form-fragment and profile-leave-requests-list-fragment. For ir-6bfl, successful create should refresh that whole nested content fragment through the shared helper; validation/no-staff errors should continue replacing only profile-leave-request-form-fragment. The broader profile content surface keeps ProfileLeaveContentFragment at target profile-content-fragment for accordion/page-section replacement and is separate from the nested leave list/form live surface. Roster self-service leave currently has no standalone typed live surface; success and validation target roster-staff-self-service-leave-form-fragment inside the roster staff self-service panel. For ir-b1lx, prefer declaring a small explicit roster self-service leave form fragment only if the surrounding roster projection cannot safely own the successful actor response; validation should remain scoped to the form. Staff admin modal leave is a separate staff-dialog context using staff-leave-request-form-fragment and staff-leave-requests-list-fragment; it is not in ir-jtmv acceptance except to avoid regressing the existing staff response context while profile/manager paths migrate.
