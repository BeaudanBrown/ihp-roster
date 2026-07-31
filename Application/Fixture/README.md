# Application fixtures

`Application.Fixture` owns reusable fixture builders used by development seeds and tests. Named fixture sets live below this namespace:

- `DevFixtures` and `Seed.*` — development scenarios
- `PayrollFixtures` — deterministic payroll/export data
- `WageSourceFixtures` — deterministic wage-source facts
- `Reset` — the closed application-table reset contract

Founder-facing Support product behavior does not belong here. Its runtime remains under `Application.Support`.

## Reset contract

`Application.Fixture.Reset.applicationTableNames` is the only reset table manifest. It contains static string literals for every table declared by `Application/Schema.sql`; it never discovers live database tables and therefore cannot include framework or migration bookkeeping accidentally. `fixture-reset-manifest-test` rejects missing, extra, duplicate, or dynamic entries. `Test.Support.withCleanDb` calls it immediately before every wrapped example and retains the existing optional reset timing around that call. Direct `seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth` callers reset once before rebuilding a named fixture. The `seed-dev` orchestrator runs the same Haskell reset first, loads reviewed award/public-holiday reference SQL, then calls the explicit after-reset builder so that reference data survives fixture construction. All reset paths retain full-table `RESTART IDENTITY CASCADE` semantics.

## Application and test variants

Shared row builders have one implementation here. `Test.Support` keeps its public test-context API and uses explicit wrappers only where behavior intentionally differs:

- users pass `UseFixturePasswordHash testPasswordHash`; application/dev builders pass `HashFixturePassword`, preserving fast fixed test hashes and runtime hashing
- test venues request roster defaults inside their existing transaction; application/dev venues use the full bootstrap configuration
- test memberships create linked profile staff for profile-complete users; application/dev memberships do not add that test convenience
- test staff creation is idempotent for an existing linked user and uses fixed contact defaults; application/dev staff creation accepts complete fixture values
- test default award labels include the venue id; application/dev labels remain `Default Level`
- `Test.Support.testPassword` remains `test-password-123`; development fixture login defaults remain unchanged

Existing `DevSeed`, controller, payroll golden, schema, and context-lifecycle suites characterize fixture row IDs, names, labels, password validity, transaction boundaries, and reset timing. Namespace moves must keep those outputs unchanged.

Do not copy builders or reset SQL into test/support modules. Add a named input here when a new intentional variant shares the underlying construction.
