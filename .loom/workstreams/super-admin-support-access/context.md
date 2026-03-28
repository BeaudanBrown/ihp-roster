# Super Admin Support Access

## Read Order

1. `AGENTS.md`
2. `IMPLEMENTATION_PLAN.md`
3. `plans/00-auth-bootstrap-memberships.md`
4. `plans/48-super-admin-support-access.md`
5. this file
6. `handoff.md`

## Objective

Add founder-only platform super-admin support access so the default founder account can switch into any active venue, act there with full read/write permissions, and remain clearly distinguishable from ordinary venue-member access.

## Coordinator Tracking

- Epic: `coordinator-xga`
- Backlog follow-up for later: `coordinator-hap`

## Settled Architecture

- add a separate platform capability on `users`
- founder bootstrap account is the only seeded `super_admin`
- no UI path to grant more super-admins
- no synthetic `venue_memberships` for support access
- dedicated support page/controller
- reuse the existing `currentVenueId` session slot for switching
- full read/write in any active venue for super-admin
- ordinary users remain membership-scoped
- audit and UI must distinguish support mode

## Important Existing Constraints

- `currentVenueId` already exists and is stored via IHP session helpers in the encrypted client session cookie
- current auth helpers are membership-centric and currently treat “no membership” as “no venue access”
- admin/config flows, exports, roster, leave, and timesheets all assume `currentVenue` is already resolved
- the support page must not be implemented by stretching venue admin screens

## Out Of Scope

- ordinary multi-venue switching for non-super-admin users
- user impersonation
- inactive-venue support tooling beyond excluding inactive venues from the switcher

## Expected Implementation Order

1. `coordinator-xga.3` platform role and venue access context
2. `coordinator-xga.1` support page and session switching
3. `coordinator-xga.4` audit/UI distinction
4. `coordinator-xga.2` controller and browser verification
