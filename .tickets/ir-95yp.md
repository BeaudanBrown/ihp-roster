---
id: ir-95yp
status: open
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

