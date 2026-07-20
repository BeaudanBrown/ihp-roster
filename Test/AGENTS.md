# Test Guidelines

## Reference
Read `../ihp/Guide/testing.markdown` for full IHP testing documentation.

## Running Tests

Tests are a devenv shell script — use `bash ./bin/in-env` outside an interactive shell:

```bash
bash ./bin/in-env hspec-test                        # compile and run the full suite, auto-sharded across local cores
bash ./bin/in-env hspec-test --match "PostsController"  # run tests matching a pattern
bash ./bin/in-env hspec-test --match "PasskeysController" --match "LiveUpdate"  # OR multiple patterns in one run
bash ./bin/in-env hspec-pure                        # pure/contract suites, no PostgreSQL reset or connection
bash ./bin/in-env hspec-db                          # DB-backed suites only, with isolated shard databases
TEST_SHARDS=1 bash ./bin/in-env hspec-test          # force serial execution
TEST_SHARDS=4 bash ./bin/in-env hspec-test          # override shard count explicitly
TEST_SHARDS=2 bash ./bin/in-env hspec-test --match "PasskeysController" --match "LiveUpdate"  # shard a focused multi-suite run
bash ./bin/in-env hspec-coverage                    # serial full-suite run with GHC HPC coverage report
bash ./bin/in-env hspec-coverage --match "PostsController"  # focused coverage run
bash ./bin/in-env verify-fast                       # typecheck + pure Hspec + fast browser tier
bash ./bin/in-env verify-full                       # complete Haskell/reachability/frontend/CSS/docs/architecture/browser gate
```

`bash ./bin/in-env hspec-test` auto-shards the full Hspec suite when no Hspec filter args are passed. DB-backed full runs cap automatic fan-out at eight shards because same-host measurements found eight shards faster than six while higher raw host core counts would add PostgreSQL reset and connection pressure without splitting the remaining indivisible suites. `TEST_SHARDS` remains an explicit override and `TEST_DB_SHARDS_MAX` can tune the automatic cap for a measured host. Each DB-backed shard gets its own ephemeral database, compiled test binary invocation, and shard log directory under `.devenv/test/`.

DB-backed Hspec and Hspec coverage use a private managed PostgreSQL cluster under
`/tmp/bepis-hspec-postgres-<uid>-<project-id>` by default. The predictable
project-scoped root is native temporary storage, not the checkout's virtiofs
mount. Every DB command reports its mode, data directory, socket, filesystem,
and effective durability settings before compilation. The managed cluster uses
`fsync=on`, `synchronous_commit=off`, and `full_page_writes=on`; only commit
acknowledgement is relaxed, and only for discardable test databases. Normal
development and deployed PostgreSQL instances are never reconfigured.

Use `hspec-pure` for the fastest broad feedback when changing pure helpers, renderers, contracts, or validation logic. Pure suites are selected by registry metadata and do not start managed PostgreSQL, run `test-db-reset`, or connect to a database. Use `hspec-db` to exercise only DB-backed suites. Both are additive lanes: `hspec-test` remains the complete canonical gate.

Normal typecheck, Hspec, and compiled E2E commands share compatible GHC object and interface files under fingerprinted `build/Verification` directories. `Test/HspecMain.hs` deliberately uses a distinct module name from the application `Main`, and coverage remains isolated under `build/TestCoverage` because HPC artifacts are incompatible. Do not point concurrent compiler invocations at the shared directory; run normal verification commands sequentially. Override `VERIFICATION_BUILD_DIR` only when a task needs its own isolated cache.

Hspec accepts repeated `--match` flags and treats them as OR filters. When checking several focused areas, prefer one command with multiple `--match` flags instead of running multiple `hspec-test --match ...` processes at the same time. Separate focused invocations compile into the shared `build/Test` directory and can race on GHC object files; they also default to the same `app_test` database unless explicitly isolated.

Focused runs default to serial execution because they are usually small. Use `TEST_SHARDS=N` with focused matches only when the matches span multiple suites and the extra database setup/log fan-out is worth it. Sharding is by `TestSuite` entry, not by individual example, so forcing shards for a single-suite match usually adds overhead without parallel speedup.

For debugging:

- `TEST_SHARDS=1` forces a single serial shard.
- `TEST_KEEP_DATABASES=1` preserves shard databases after the run instead of dropping them.
- `.devenv/test/latest/` points at the most recent shard log directory.
- `test-postgres status` reports the managed instance; `test-postgres stop`
  cleanly stops it and deletes its disposable data; `test-postgres recreate`
  deliberately replaces it.
- Set `TEST_POSTGRES_MODE=external` together with an explicit
  `TEST_DB_SOCKET` only when comparing against another PostgreSQL instance.
  An inherited `PGHOST` alone never opts out of managed mode; this prevents the
  normal devenv server from being selected accidentally. External mode never
  changes that server's settings.
- `TEST_POSTGRES_ROOT` may select another managed location, but known virtual
  or shared filesystems are refused unless
  `TEST_POSTGRES_ALLOW_NON_NATIVE=1` is explicitly set for diagnostics.

## Reproducible Baselines

Use `bin/hspec-baseline` for performance evidence rather than ad-hoc timing. It
holds the host-global `/tmp/bepis-exclusive-performance.lock`, refuses to
measure alongside another known full test/profile process, separates compile,
shard database, Hspec, reset, and cleanup phases, and samples PostgreSQL
connections/waits at a bounded rate. Raw artifacts belong under the ignored
`output/hspec-baseline/` tree.

```bash
bash ./bin/in-env ./bin/hspec-baseline run \
  --name local-full-6 --output output/hspec-baseline/local-full-6 -- \
  env TEST_SHARDS=6 hspec-test --format=progress --no-color --times

bash ./bin/in-env ./bin/hspec-baseline inventory \
  --check docs/archive/hspec-suite-inventory-2026-07-19.json \
  --output output/hspec-baseline/inventory-check.json
```

Use one warm-up plus three measured runs for short comparisons. Report failed
runs separately, do not include them in medians, and label single expensive
full runs as such. `HSPEC_METRICS_DIR`, the phase metric variables, and
`HSPEC_BASELINE_PROBE` are internal instrumentation controls; leave them unset
during normal Hspec use. The opt-in fixture/application probe is deliberately
absent from `Test/Suite.hs` and must never change canonical example counts.
The issue #198 protocol and baseline are archived in
`docs/archive/hspec-critical-path-baseline-2026-07-19.md`.

## Coverage

Use `bash ./bin/in-env hspec-coverage [hspec-args...]` when adding or materially changing Hspec coverage. It compiles the test runner with GHC HPC instrumentation, runs serially against the isolated `app_test_coverage` database, prints an app-source per-module text report, and writes durable artifacts under `output/coverage/hspec/latest/`:

- `report.txt` — human-readable app-source per-module coverage (`Application/` and `Web/`)
- `report.xml` — machine-readable app-source summary for later automation
- `html/hpc_index.html` — annotated app-source HTML coverage
- `raw-report.txt` — unfiltered HPC report for all instrumented modules, including generated and test modules

The coverage command is intentionally separate from `hspec-test`: use `hspec-test` for the normal fast correctness check, then run `hspec-coverage` when the task needs coverage statistics or when validating that new tests exercise the intended modules and branches.

## Shard Registry

`Test/HspecMain.hs` is only the runner entrypoint. Its distinct module name allows normal checks to share compatible GHC artifacts with the application `Main` module. The authoritative suite registry lives in `Test/Suite.hs`.

When adding a new spec module:

1. Import it in `Test/Suite.hs`
2. Add a `pureSuite "Label" weight Module.tests` or `databaseSuite "Label" weight Module.tests` entry to `allSuites`. A pure suite must pass with PostgreSQL unavailable; classify any suite that opens a DB connection as database-backed.
3. Choose an initial `weight` that roughly matches the suite's expected runtime in seconds, rounded to the nearest 5 or 10 seconds. Use a small value such as `5` or `10` for tiny pure/contract specs.

`Test/Suite.hs` uses weighted greedy sharding independently within the selected all/pure/DB lane. The suite order is no longer a balancing mechanism; do not manually cluster or reorder suites to tune shards unless the weighted algorithm itself is changing. Keep large controller families registered at their independently runnable child-spec boundary while retaining a common label prefix such as `AdminController.*` or `RosterWeeksController.*` for broad matching.

To rebalance weights when full-suite shard times drift:

1. Run the full suite:
   ```bash
   bash ./bin/in-env hspec-test
   ```
2. Inspect shard headers and durations:
   ```bash
   for f in .devenv/test/latest/shard-*.log; do
       echo "--- $(basename "$f")"
       grep -E 'Hspec shard|Finished in|examples' "$f"
   done
   ```
3. Identify slow shards from `Finished in ... seconds` and the suite list in the `Hspec shard N/M weight=... [...]` header.
4. If one suite appears to dominate a slow shard, estimate it with a focused run:
   ```bash
   bash ./bin/in-env hspec-test --match "PasskeysController"
   ```
5. Update only the relevant `suiteWeight` values in `Test/Suite.hs`. Prefer approximate relative runtime; round to the nearest 5 or 10 seconds and avoid overfitting tiny differences.
6. Re-run the full suite when practical, or at least run `TEST_SHARDS=N bash ./bin/in-env hspec-test --match "some small suite"` to verify shard selection still works and prints weighted headers.

Do not reintroduce a hard-coded linear `hspec do ...` list in `Test/HspecMain.hs`; that bypasses shard selection.

## DB-Backed Controller Tests

When auth or controller setup touches the database, prefer the shared helpers in `Test/Support.hs` instead of `mockContextNoDatabase` alone.

For every new or changed input boundary, add focused coverage for missing required params, malformed typed values, oversized text, whitespace-only text, cross-venue/cross-group ids, and suspicious payloads such as script tags or formula-looking text. The expected result should be a validation rerender, controlled 4xx/redirect, or no-op mutation, not an unhandled 500.

When testing request-derived ids, include both malformed UUID text and well-formed ids outside the current tenant/venue/group. Parsing safety and scope authorization are separate assertions.

For exports, include CSV cells beginning with `=`, `+`, `-`, `@`, tab, carriage return/newline, whitespace-prefixed formulas, quotes, commas, and newlines so `csvCell` keeps both formula neutralization and CSV quoting intact.

For URL helpers, include existing-query URLs, spaces, ampersands, equals signs, percent signs, empty values, and token-like values. Callers should use `appendQueryParams` rather than manual string concatenation.

Useful patterns:

- `tests = aroundAll withDatabaseTestContext do ...` creates one DB-backed
  context per suite and releases its model pool/listener after success, failure,
  exception, or asynchronous interruption.
- `withContext do withCleanDb do ...` resets the DB between examples.
- Do not use `beforeAll testContext`, `mockContextNoDatabase`, or another
  unbracketed context constructor. The deprecated path retains Hasql pools until
  process exit. `Test.ContextLifecycleSpec` is the regression contract.
- `createVenueWithConfig`, `createUserRecord`, `createUserRecordWithPlatformRole`, `createVenueMembershipRecord`, `createStaffRecord`, and related helpers to seed only the rows the example needs. Shared test-user builders use the fixed valid `testPasswordHash`; do not reintroduce per-user `hashPassword` calls. Sessions and user-creation specs retain real verifier and runtime hashing coverage.
- `withUserAndCurrentVenue user venueId do ...` when the request needs both authenticated user session and `currentVenueId`
- `withControllerTestContext do ...` when the test needs a real `ControllerContext`, e.g. to call `beforeLogin` and then `getSession`

`withCleanDb` should leave the test database truly empty. If automation must preserve bootstrap/manual accounts, solve that by running tests against an isolated database instead of weakening `withCleanDb`.

For approved timesheet fixtures, use `createApprovedTimesheetEntryRecord` or `createApprovedTimesheetEntryRecordAt`. Do not seed approval by setting only `isApproved`; the schema requires `approved_at`, `approved_by_user_id`, `staff_pay_version_id`, and `shift_type_pay_version_id` to move together.

Leave request `end_date` is exclusive: a one-day leave request is `start_date = day`, `end_date = day + 1`. Do not seed `start_date == end_date`; the schema rejects empty ranges.

Shard databases are cloned from an immutable content-addressed schema template keyed by IHP schema, app schema, and app fixtures. Missing-template creation is serialized across shards. Set `TEST_DB_RESET_MODE=direct` to replay schema files when diagnosing template/reset behavior. E2E fixture resets always use the direct path because their data is run/date-sensitive. Per-example `withCleanDb` remains an explicit full-table truncate; do not replace it with an outer transaction because normal helpers use legitimate nested transactions and some tests require committed visibility.

The managed cluster is persistent across healthy test commands so templates can
be reused, but its contents have no recovery contract. If the postmaster is not
running—whether after a crash, interruption, reboot, or explicit stop—the next
`ensure` deletes the complete owned data directory and runs `initdb`; it never
attempts data repair or WAL recovery. A marker tied to the current uid and
checkout protects deletion, non-empty unowned roots are refused, and the
postmaster must not inherit the manager lock. `TEST_POSTGRES_DURABILITY=durable`
is available for same-instance comparisons. `custom` plus explicit values for
all three durability settings is benchmark-only; these settings still apply
solely to a newly initialized managed test cluster.

The shard architecture assumes:

- every parallel shard owns an isolated ephemeral database
- examples within a shard still reset their own state with `withCleanDb`
- no spec may depend on rows created by another spec module or another example

If a helper or fixture needs state to persist across examples, that is usually a test-design bug. Prefer explicit builders that recreate only the rows the example needs. When several read-only examples would each construct the same unusually expensive immutable fixture, consolidate their assertions into one behaviorally named example rather than sharing mutable database state across examples; `DevSeedSpec` is the canonical pattern.

For fixed payroll export correctness, prefer a dedicated golden spec with:

- reusable fixture builders under `Test/Support/`
- committed expected outputs under `Test/Fixtures/exports/`
- exact CSV/ZIP comparisons

Use browser tests only to prove the exports workflow still works. Keep detailed payroll-number validation in fast controller-level specs. `FixedExportGoldenSpec` also owns repeated-job CSV/ZIP determinism; do not restore a browser-only byte-comparison loop.

Current product scope is the fixed export catalog. Historical report-definition variants such as `kitchen` are not a supported test path.

The fixed-export golden suite in `Test/Controller/FixedExportGoldenSpec.hs` is the main correctness oracle for payroll output. Keep it focused on:

- exact `staff_hours` CSV output
- approved vs unapproved and trial-row inclusion boundaries
- break-adjusted day totals and overnight bucketing
- snapshot-pinned stability after live pay-config changes
- mixed-snapshot export metadata when approved entries span versions

For manual inspection, `seed-dev` loads a broader exploration dataset outside the test suite. Keep the exact golden fixture stable for controller tests, while the manual script projects a busier multi-venue, multi-group week plus support/bootstrap scenarios onto the current app week for easier browser exploration. The human default is `just seed-dev`, which now always wipes and reseeds `app` before loading the fixture. Keep the reusable test-support fixture modules deterministic enough that the manual dev seed does not weaken golden assertions.

Example shape:

```haskell
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "LeaveRequestsController" do
        it "scopes manager queries to the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
```

## Adding Tests for a New Controller

When adding a new controller (e.g., `PostsController`), create a corresponding spec:

1. Create `Test/Controller/PostsSpec.hs`:
   ```haskell
   module Test.Controller.PostsSpec where

   import Network.HTTP.Types.Status
   import IHP.Prelude
   import IHP.Test.Mocking
   import IHP.HaskellSupport
   import Test.Hspec
   import Test.Support
   import Generated.Types
   import Web.Routes
   import Web.Types
   import Web.Controller.Posts ()
   import Web.FrontController ()
   import Network.Wai
   import IHP.ControllerPrelude

   tests :: Spec
   tests = aroundAll withDatabaseTestContext do
       describe "PostsController" do
           it "renders the index page" $ withContext do
               response <- callAction PostsAction
               response `responseStatusShouldBe` status200

           it "renders the new post form" $ withContext do
               response <- callAction NewPostAction
               response `responseStatusShouldBe` status200
               response `responseBodyShouldContain` "New Post"

           it "creates a post via form submission" $ withContext do
               response <- callActionWithParams CreatePostAction
                   [("title", "Test Post"), ("body", "Test body")]
               response `responseStatusShouldBe` status302
   ```

2. Register it in `Test/Suite.hs`:
   ```haskell
   import qualified Test.Controller.PostsSpec

   allSuites =
       [ TestSuite "StaticController" Test.Controller.StaticSpec.tests
       , TestSuite "PostsController" Test.Controller.PostsSpec.tests
       ]
   ```

## Test Context Ownership

- `withDatabaseTestContext` from `Test.Support` is the only supported shared
  application-context constructor. It applies test environment configuration
  centrally and delegates ownership to IHP's bracketed `withMockContext`.
- Use it with Hspec's `aroundAll`, not `beforeAll`; `aroundAll` gives the
  bracket a continuation whose completion releases the pool and PG listener.
- A genuinely no-database suite belongs in the registry's pure lane and must
  not construct a `MockContext`, call `withCleanDb`, or open PostgreSQL. A
  controller spec using `withContext`, authentication/current-venue setup, or
  database-backed middleware is a database suite even if one example only
  renders or redirects.
- Never use the deprecated name `mockContextNoDatabase`: in current IHP it
  still creates a real `ModelContext` pool, despite its historical name, and
  it has no release continuation.

## Available Test Helpers

- `withDatabaseTestContext` — Bracket a DB-backed IHP mock context with proper resource cleanup.
- `callAction SomeAction` — Call a controller action, returns `Response`.
- `callActionWithParams SomeAction [("key", "value")]` — Call with form params
- `responseStatusShouldBe response status200` — Assert HTTP status
- `responseBodyShouldContain response "text"` — Assert body contains text
- `responseBodyShouldNotContain response "text"` — Assert body does not contain text
- `responseBody response` — Extract response body as `LBS.ByteString`
- `withUser user do ...` — Set current user for auth-protected actions

Do not add new `pendingWith "requires real DB"` placeholders for normal
controller work without checking `Test/Support.hs` first. Most auth-gated and
venue-scoped controller tests should use the bracketed DB context directly.

## What to Test

- **Every controller action** should have at least a status code assertion
- **Form submissions** (Create/Update) should verify redirect and side effects
- **Auth-protected actions** should test both authenticated and unauthenticated access
- **View content** — assert key content appears in the response body

## Session Notes

`IHP.Test.Mocking.withUser` only seeds the login session key. If the app depends on additional session state, add it through `withSessionValues`/`withUserAndCurrentVenue` in `Test/Support.hs`.

This matters for venue-scoped auth because `beforeLogin` writes `currentVenueId`, and request init reads that session value back on subsequent requests.

For founder support-access tests, prefer `createUserRecordWithPlatformRole ... (Just SuperAdminRole)` plus `withUserAndCurrentVenue` on a foreign venue instead of creating fake cross-venue memberships. The request context should then resolve `currentVenue` with `currentVenueMembershipOrNothing = Nothing`.

- For HTML scoping assertions, avoid broad `responseBodyShouldNotContain` checks on generic UI text that also appears in static controls (for example weekday names in a shared `<select>`). Prefer row-specific combined labels or unique seeded names.
- When a spec seeds prerequisite rows and then creates more rows of the same table, query the created record by a unique field (or explicit ordering) instead of bare `fetchOne`, which may return the older fixture row.
