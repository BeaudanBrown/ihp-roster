---
id: ir-0mfi
status: closed
deps: [ir-olct, ir-pcdb, ir-cbad]
links: []
created: 2026-06-16T01:03:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-3qq9
tags: [agent-loop, docs, tests]
---
# Document and verify trial staff adoption invite flow

Add final documentation and regression coverage for the adopted trial staff account lifecycle.

## Design

Update roster/access/staff docs or specs with the implemented contract. Add focused tests for stale/tampered adoption links, double redemption, live touched resources, mail copy/url, and normal invite compatibility. Run typecheck and focused Hspec, then full Hspec if prior slices did not cover enough.

## Acceptance Criteria

Living docs describe that trial staff can be converted only through invitation-created new accounts; test suite covers success and rejection paths; full epic acceptance is verified and tickets are closeable.


## Notes

**2026-06-16T01:34:03Z**

Finalized documentation, mail copy, and verification. Documented trial staff adoption invites in access-control/auth spec and roster-week spec. Venue invitation mail now uses claim-profile copy for staff-linked invitations while keeping the existing /NewUser?invitationId=<uuid> link. Added mail coverage for adoption invitations. Verification: focused StaffController/UsersController/Mail templates Hspec passed (47 examples), typecheck passed, and full hspec-test passed across 8 shards after rerun with longer timeout (initial full run hit the 120s harness timeout before completion).
