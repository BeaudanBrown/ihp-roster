# Super Admin Support Access Handoff

## Status

`coordinator-xga.1` is implemented locally and verified. The lane now moves to support-mode audit/UI distinction and broader verification.

## Current Decision State

- founder account should become the only seeded `super_admin`
- super-admin has full read/write access in any active venue
- switching should happen from a dedicated support page
- switching should reuse the existing `currentVenueId` session slot
- ordinary users remain membership-scoped
- support-mode actions must be auditable and visibly distinguished

## Implemented So Far

- added `users.platform_role` with enum value `super_admin`
- seeded the founder bootstrap fixture as `platform_role = 'super_admin'`
- updated request-scoped venue resolution so a super-admin can resolve any active venue without a synthetic `venue_memberships` row
- kept real memberships when they exist; support-mode shape is now:
  - `currentVenue` resolved
  - `currentVenueMembershipOrNothing = Nothing`
  - `currentVenueRoleOrNothing = Nothing`
  - `currentUserIsSuperAdmin = True`
- updated `ensureCurrentVenue` and `hasRole` so ordinary users stay membership-scoped while super-admin bypass works in active venues
- added schema/helper/controller tests proving:
  - founder/super-admin can reach a foreign venue admin page without membership
  - foreign `currentVenueId` session values resolve correctly for super-admin
  - before-login venue seeding still works for a super-admin without memberships
- added a dedicated `SupportController` and `SupportAction`
- added a founder-only `support` link in the authenticated header
- support page lists active venues and uses a simple dropdown form to switch the current session venue
- added `SwitchSupportVenueAction`, which writes the selected active venue into the existing `currentVenueId` session slot and redirects back to the support page
- added controller coverage proving:
  - ordinary venue admins are denied the support page
  - super-admin can open the support page and see active venues
  - super-admin can post the switch action successfully

## Verification

- `bash ./bin/in-env regen-types`
- `bash ./bin/in-env make db`
- `bash ./bin/in-env typecheck`
- `bash ./bin/in-env hspec-test` → `193 examples, 0 failures`
- `bash ./bin/in-env typecheck`
- `bash ./bin/in-env hspec-test --match support` → `4 examples, 0 failures`

## Next Ready Work

Move to `coordinator-xga.4`:

- emit dedicated support-access audit when switching venues
- add clear support-mode UI indication for the currently selected venue
- then finish `coordinator-xga.2` with controller/browser verification of full founder switching flow

## Useful Existing Anchors

- `Application/Helper/Controller.hs` currently owns `currentVenueId`, current venue resolution, and role guards
- `Web/Controller/Sessions.hs` seeds `currentVenueId` after login
- `Web/View/Layout.hs` owns the authenticated header and is the natural place for a small support-mode indicator
- `Application/Fixtures.sql` seeds the founder bootstrap login
- `currentUserIsSuperAdmin` now exists in `Application/Helper/Controller.hs`; use it rather than inferring founder access from venue roles or `users.user_role`

## Guardrails

- do not overload `venue_memberships` to represent support access
- do not add UI for granting extra super-admins
- keep ordinary users on the existing membership-scoped model
