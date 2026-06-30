---
id: ir-95yp
status: closed
deps: [ir-63go]
links: []
created: 2026-06-30T04:48:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [haskell, controller, migration]
---
# Migrate SessionsController to Bepis wrappers

Use the smallest useful controller as the first app migration to prove wrapper ergonomics.

## Design

Migrate Web.Controller.Sessions so beforeAction/action bodies delegate through Bepis controller/action wrappers. Classify NewSessionAction, CreateSessionAction, DeleteSessionAction, VerifyEmailAction, and ResendVerificationAction with appropriate action/response kinds while preserving IHP behavior.

## Acceptance Criteria

SessionsController behavior and tests pass. The migrated controller has no raw top-level action body that bypasses Bepis wrappers. Architecture facts can identify typed-wrapper source for SessionsController actions.


## Notes

**2026-06-30T05:07:11Z**

Verification: bash ./bin/in-env typecheck passed. Full hspec-test was run and failed in unrelated existing guard areas (LiveSurfaceGuard flags Application/Helper/UiRegion.hs raw data-bepis attributes/Text selectors; not touched by this ticket) plus a venue-scoped manager query failure in another shard. No Sessions-specific regressions were observed.
