# Migration Check Authority

This inventory prevents a focused SQL test from being mistaken for deployment
rehearsal evidence.

## Deployment and runner authority

Only `migration-rehearsal` provides deployment-path evidence. It reconstructs an
exact Git predecessor, uses the candidate-pinned IHP migration runner, verifies
recorded revisions and fresh-schema convergence, and executes revision-owned
fixtures under `Application/Migration/Rehearsal/`.

`billing-migration-check` is a focused wrapper over that shared harness. Its
predecessor is the parent of the commit that introduced revision `1784761930`.
The isolated candidate schema composes that predecessor schema with the reviewed
migration SQL so PostgreSQL column ordinals match the upgrade result; only the
upgrade side records and executes the revision through IHP `migrate`. Its fixture
proves billing Customer, Subscription, Event, and Venue rows survive that runner
path and that temporary backfill defaults are removed. PostgreSQL lifecycle and
cleanup remain delegated to `test-postgres` and `migration-rehearsal`.

No other check described below is deployment or migration-runner evidence.

## Retained direct-SQL semantic checks

`Test/DatabaseProtectionSpec.hs` executes selected migration SQL through Hasql
inside the Hspec database transaction. The fixtures use isolated schemas or
focused current-schema setup to cheaply exercise row projections, constraints,
triggers, repair behavior, and destructive preflight semantics for revisions
`1785813000`, `1785826000`, `1785839000`, `1787001000`, `1787003000`,
`1787005000`, `1787006000`, `1788100000`, and `1788100100`. The extracted
resolver from `1784932300` tests DST function semantics only. These checks do
not reconstruct a Git predecessor, advance `schema_migrations`, or claim runner
authority; retaining them gives narrow domain failures without duplicating the
shared harness.

`Test/DurableLiveInvalidationSpec.hs` applies revision `1788001100` directly to
a current-schema fixture to prove its foreign-key repair preserves version
authority. This is a repair-SQL semantics check, not evidence that the migration
runner can deploy the revision.

`bin/date-native-roster-migration-check` composes the corresponding focused
Hspec semantics checks with generated-type and application authority checks. Its
help intentionally states that it is not a production migration runner.

## Retained source-contract checks

The following files read migration text but do not execute it:

- `Test/SchemaSpec.hs` checks additive/destructive vocabulary, required DDL and
  runbook coupling.
- `Test/EmailDeliverySpec.hs` checks the bounded sets and terminal-state policy
  encoded by email job cutover revisions.
- `Test/AccountSecurityEmailSpec.hs` checks that token-ciphertext rollout remains
  additive.

These are narrow source ownership and policy guards. They neither prove SQL
parsing nor provide deployment evidence. Runner behavior and whole-schema
convergence remain owned exclusively by `migration-rehearsal`.
