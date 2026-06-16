---
id: ir-3qq9
status: open
deps: []
links: []
created: 2026-06-16T01:03:30Z
type: epic
priority: 1
assignee: beaudan
tags: [agent-loop, trial-staff, invites]
---
# Trial staff account adoption invites

Let venues invite a new staff user to claim an existing trial staff placeholder. The signup link should prefill from the trial staff row, create a new account only, and link the existing staff row so roster slots, roster groups, preferences, pay/profile data, and history remain attached to the same staff id.

## Design

Extend existing venue_invitations rather than introducing a parallel public signup flow. Keep invitation UUID links for this slice. Add an optional same-venue staff adoption target to venue invitations; regular invites keep staff_id/null and current behavior. Adoption accepts pending worker-only invites by creating a new verified user, creating worker venue membership, and updating the existing active unarchived trial staff row from user_id NULL to the new user id inside the same transaction. Signup fields remain editable but are prefilled from the trial row. Existing accounts cannot redeem adoption invites.

## Acceptance Criteria

A venue staff sender who can create normal worker invitations can invite an active trial staff row; the emailed/special link opens the existing account creation page prefilled with trial details; accepting creates a new user and worker membership and links the existing staff row without changing its id; previous roster slots/group assignments remain attached; normal invitations still work; stale/cross-venue/already-linked/adopted invitations are rejected safely; behavior is documented and covered by focused controller, mutation, schema, and mail tests.

