---
id: ir-cbad
status: closed
deps: [ir-patj, ir-pcdb]
links: []
created: 2026-06-16T01:03:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-3qq9
tags: [agent-loop, mutation, invites]
---
# Accept adoption invites by linking existing staff

Redeem staff-linked invitations by creating a new account and linking the existing trial staff row instead of creating a new staff row.

## Design

Extend acceptVenueInvitation in Web.Users.Mutations. Inside one transaction create verified user, provision worker membership, update the targeted trial staff row user_id plus submitted editable profile fields, mark invitation accepted, and audit the adoption. Preserve the staff id so existing roster slots, roster groups, preferences, pay config, and history remain attached. Reject existing-user email collisions and already-consumed/stale targets.

## Acceptance Criteria

Acceptance creates exactly one new user and worker membership, updates the original staff row user_id, preserves staff id and roster slot references, marks the invite accepted, records audit metadata, and emits admin-invites plus adopted-staff touched resources. Normal invitation acceptance still creates/updates linked staff as before.


## Notes

**2026-06-16T01:26:56Z**

Implemented adoption invite acceptance. CreateUserAction now revalidates staff-linked invite targets before account creation. acceptVenueInvitation branches on invitation.staff_id: normal invites keep ensureLinkedStaffRecord behavior; adoption invites update the existing active unarchived unlinked staff row with the new user_id and submitted editable profile fields, preserving staff id and roster-slot references. Accepted adoption invites touch admin invite plus adopted staff live resources and use context-free invalidation because public signup has no current venue. Added UsersController coverage for successful adoption, stale/already-linked rejection, touched resources, and regular invite compatibility. Verified focused UsersController Hspec and typecheck.
