---
id: ir-pcdb
status: closed
deps: [ir-patj]
links: []
created: 2026-06-16T01:03:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-3qq9
tags: [agent-loop, ui, invites]
---
# Prefill signup from trial staff adoption invites

Render the account creation form for adoption invitations using the target trial staff details as editable defaults.

## Design

Update NewUserAction to fetch and validate the adoption target when invitation.staff_id is present. Reuse the existing invited profile details form; pass the existing Staff row instead of a blank/new staff record. Adjust page/mail copy only as needed to clarify that the user is claiming an existing roster profile.

## Acceptance Criteria

Valid adoption links show Accept Invitation with editable fields prefilled from the trial staff row; expired/revoked/already-linked/cross-venue targets show the invalid invitation page; regular invitation rendering remains unchanged.


## Notes

**2026-06-16T01:23:34Z**

Implemented adoption-invite signup prefill. NewUserAction resolves invitation.staff_id to same-venue active unarchived unlinked staff and renders the existing invitation signup form with that staff row as editable defaults. Stale/already-linked targets fall back to the invitation-required page. Added copy explaining claim of an existing trial staff profile and controller coverage for prefill and invalid linked target; regular invitation tests still pass under UsersController focused run. Verified typecheck.
