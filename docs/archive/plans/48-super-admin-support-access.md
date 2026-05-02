# Pipeline 48 — Super Admin Support Access

Read after `IMPLEMENTATION_PLAN.md` and `docs/archive/plans/00-auth-bootstrap-memberships.md`.

## Goal

Add founder-only platform super-admin support access so the default founder account can switch into any active venue, act there with full read/write permissions, and remain clearly distinguishable from ordinary venue-member access.

## Why This Exists

The app currently resolves operational authority entirely from `venue_memberships` and persists exactly one `currentVenueId` in the IHP session cookie. That works for normal venue-scoped users, but it breaks the founder support workflow:

- the founder bootstrap account only has a real membership in the default dev venue
- support/test fixtures can create additional venues that the founder cannot enter
- forcing founder-wide access through synthetic venue memberships would pollute business data and blur the distinction between platform support access and real venue authority

The right model is therefore:

- platform-level support capability on `users`
- venue-level business authority on `venue_memberships`
- explicit session-based venue switching through a support surface

## Settled Direction

- add a separate platform capability on `users`, not on `venue_memberships`
- seed the founder bootstrap account as the only `super_admin`
- expose no UI path to grant or revoke additional super-admins
- do not create synthetic membership rows for support access
- reuse the existing `currentVenueId` session slot for switching
- give super-admin full read/write access in any active venue
- keep ordinary users membership-scoped only
- use a dedicated support page, not venue admin screens, for cross-venue switching
- distinguish support-mode actions in audit and UI

## Current Session Model

`currentVenueId` already exists and should remain the switching primitive:

- key: `currentVenueId`
- set/read from `Application/Helper/Controller.hs`
- stored through IHP `setSession` / `getSession`
- therefore persisted in the encrypted, signed client session cookie rather than in a database table

This means venue switching can stay cheap and explicit: the support page writes a different venue id into the existing session slot.

## Scope

- platform super-admin schema and parsing helpers
- founder bootstrap fixture updates
- request-scoped venue access-context refactor
- support-only venue switch page
- session-based switching into any active venue
- support-mode audit distinction
- support-mode UI indication
- controller and browser verification

## Non-Goals

- ordinary multi-venue switching for non-super-admin users
- user impersonation
- bulk support tooling beyond venue switching
- inactive-venue recovery tooling beyond excluding inactive venues from the support switcher

## Implementation Slices

### 1. Platform role and access context

- add `platform_role` to `users` with a dedicated enum/value for `super_admin`
- keep `users.user_role` unchanged for now; do not overload it
- seed the founder bootstrap account with the new platform role
- refactor request-scoped access resolution so a super-admin can resolve an active venue without a `venue_memberships` row
- preserve `currentVenueMembershipOrNothing` as `Nothing` for support access rather than inventing fake memberships
- update role guards so super-admin bypasses venue-role minimums while ordinary users remain membership-scoped

### 2. Support page and switching flow

- add a dedicated `SupportController`
- add a support page visible only to super-admin
- list all active venues there, with room for future support tools
- add an explicit switching action that updates `currentVenueId` in session
- redirect back into a normal venue-scoped screen after switching

### 3. Audit and UI distinction

- emit a dedicated support access event when the founder switches into a venue
- distinguish later venue-scoped mutations performed through support access
- add a small support-mode indicator in the layout so the founder can see which venue they are acting inside

### 4. Verification

- schema/helper tests for the new platform role and access resolution
- controller tests for support-page auth, venue switching, and cross-venue access
- negative tests proving ordinary venue admins/managers/workers cannot use the support surface
- one browser test proving founder venue switching through the support page

## Recommended File Touchpoints

- `Application/Schema.sql`
- `Application/Fixtures.sql`
- `Application/Helper/Controller.hs`
- `Application/Helper/View.hs`
- `Web/FrontController.hs`
- `Web/Types.hs`
- `Web/Controller/Sessions.hs`
- `Web/Controller/*` auth guards that currently assume membership-only access
- `Web/View/Layout.hs`
- new support controller/view files
- `Test/SchemaSpec.hs`
- controller specs for auth/support switching
- one Playwright support-access flow

## Acceptance Checks

Done when:

1. the founder bootstrap account has a separate platform super-admin capability
2. the founder can switch into any active venue without a real membership row there
3. venue-scoped read/write flows work for super-admin after switching
4. ordinary users remain constrained to their venue memberships
5. support-mode actions are visibly and durably distinguishable from ordinary venue-member actions
