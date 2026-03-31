# Test Guidelines

## Reference
Read `IHP/Guide/testing.markdown` for full IHP testing documentation.

## Running Tests

Tests are a devenv shell script — use `bash ./bin/in-env` outside an interactive shell:

```bash
bash ./bin/in-env test                        # compile and run all tests
bash ./bin/in-env test --match "PostsController"  # run tests matching a pattern
```

## DB-Backed Controller Tests

When auth or controller setup touches the database, prefer the shared helpers in `Test/Support.hs` instead of `mockContextNoDatabase` alone.

Useful patterns:

- `tests = beforeAll testContext do ...`
- `withContext do withCleanDb do ...` to reset the DB between examples
- `createVenueWithConfig`, `createUserRecord`, `createUserRecordWithPlatformRole`, `createVenueMembershipRecord`, `createStaffRecord`, and related helpers to seed only the rows the example needs
- `withUserAndCurrentVenue user venueId do ...` when the request needs both authenticated user session and `currentVenueId`
- `withControllerTestContext do ...` when the test needs a real `ControllerContext`, e.g. to call `beforeLogin` and then `getSession`

`withCleanDb` should leave the test database truly empty. If automation must preserve bootstrap/manual accounts, solve that by running tests against an isolated database instead of weakening `withCleanDb`.

For payroll/report export correctness, prefer a dedicated parity spec with:

- reusable fixture builders under `Test/Support/`
- committed expected outputs under `Test/Fixtures/exports/`
- exact CSV/ZIP comparisons

Use browser tests only to prove the exports workflow still works. Keep detailed payroll-number validation in fast controller-level specs.

Current product scope for payroll verification is one canonical payroll CSV for the primary/only venue staff group. If historical filtered variants such as `kitchen` remain in tests, keep them explicitly marked as regression-only rather than treating them as the active product target.

The canonical payroll parity suite in `Test/Controller/PayrollExportParitySpec.hs` is the main correctness oracle for that export. Keep it focused on:

- exact `staff_hours` CSV output
- approved vs unapproved and trial-row inclusion boundaries
- break-adjusted day totals and overnight bucketing
- snapshot-pinned stability after live pay-config changes
- mixed-snapshot export metadata when approved entries span versions

For manual inspection, `seed-dev` loads a broader exploration dataset outside the test suite. Keep the exact parity fixture stable for controller/golden tests, while the manual script projects a busier multi-venue, multi-group week plus support/bootstrap scenarios onto the current app week for easier browser exploration. The human default is `just seed-dev`, which now always wipes and reseeds `app` before loading the fixture. Keep the reusable test-support fixture modules deterministic enough that the manual dev seed does not weaken parity assertions.

Example shape:

```haskell
tests :: Spec
tests = beforeAll testContext do
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
   import IHP.FrameworkConfig
   import IHP.HaskellSupport
   import Test.Hspec
   import Config
   import Generated.Types
   import Web.Routes
   import Web.Types
   import Web.Controller.Posts ()
   import Web.FrontController ()
   import Network.Wai
   import IHP.ControllerPrelude

   tests :: Spec
   tests = beforeAll (mockContextNoDatabase WebApplication config) do
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

2. Register it in `Test/Main.hs`:
   ```haskell
   import qualified Test.Controller.PostsSpec

   main = hspec do
       Test.Controller.StaticSpec.tests
       Test.Controller.PostsSpec.tests
   ```

## Available Test Helpers (from `IHP.Test.Mocking`)

- `mockContextNoDatabase` — Create a mock context without a real DB connection (for static/form-render tests)
- `callAction SomeAction` — Call a controller action, returns `Response`
- `callActionWithParams SomeAction [("key", "value")]` — Call with form params
- `responseStatusShouldBe response status200` — Assert HTTP status
- `responseBodyShouldContain response "text"` — Assert body contains text
- `responseBodyShouldNotContain response "text"` — Assert body does not contain text
- `responseBody response` — Extract response body as `LBS.ByteString`
- `withUser user do ...` — Set current user for auth-protected actions

## `mockContextNoDatabase` Limitations

`mockContextNoDatabase` sets up a connection pool but leaves the underlying DB connection `undefined`. Any action that touches the database at runtime will return a **500**.

This means:

- **Safe to test** with `mockContextNoDatabase`: rendering forms, unauthenticated redirects (`ensureIsUser` with no session), any action that never queries the DB
- **Cannot test** with `mockContextNoDatabase` by itself: `CreateSessionAction`/`DeleteSessionAction`, `withUser` + an auth-gated page, or any controller path that resolves current venue/membership from the DB
- **Can test** these flows now by combining `testContext` with the helpers in `Test/Support.hs`

Do not add new `pendingWith "requires real DB"` placeholders for normal controller work without checking `Test/Support.hs` first. Most auth-gated and venue-scoped controller tests should now be implemented directly.

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
