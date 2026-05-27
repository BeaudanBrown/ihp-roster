# E2E Testing — Agent Guide

## Running Tests

All commands require `bash ./bin/in-env` (or an already active devenv shell). Do not rely on bare `npx playwright ...` in Loom or other automation contexts; the repo wrapper resolves the repo-local Playwright test CLI inside the dev shell so the runner matches the `@playwright/test` package imported by the specs.

```bash
# Run the full e2e suite, auto-sharded up to two app-server shards by default
bash ./bin/in-env e2e

# Run a specific test file
bash ./bin/in-env e2e e2e/auth.spec.ts

# Run in headed mode (visible browser)
bash ./bin/in-env e2e --headed

# Run with Playwright UI
bash ./bin/in-env e2e --ui

# Take a screenshot of a page
bash ./bin/in-env screenshot http://localhost:8000/Dashboard dash.png

# Take a screenshot of a protected page with reusable login flow
bash ./bin/in-env screenshot-page /RosterWeeks roster.png --selector '.roster-grid'

# Same flow, but tolerant of cold IHP boot/compile time
bash ./bin/in-env screenshot-page /RosterWeeks roster.png \
  --selector '.roster-grid' \
  --navigation-timeout-ms 120000 \
  --selector-timeout-ms 120000

# Run the dedicated mobile/tablet experience checks
bash ./bin/in-env e2e e2e/mobile-experience.spec.ts

# Run the roster-specific mobile/tablet baseline
bash ./bin/in-env e2e e2e/roster-mobile.spec.ts

# Capture roster mobile screenshots and layout metrics in the Playwright report
bash ./bin/in-env e2e-roster-mobile-screenshots

# Capture authenticated roster screenshots against the running dev app
bash ./bin/in-env screenshot-roster-mobile output/playwright/roster-mobile/latest

# View the last test report
bash ./bin/in-env e2e-report

# Force serial execution
E2E_SHARDS=1 bash ./bin/in-env e2e

# Disable Playwright retries for faster local/agent iteration
bash ./bin/in-env env PLAYWRIGHT_RETRIES=0 e2e e2e/auth.spec.ts

# Use Playwright CLI for exploratory browser automation
bash ./bin/in-env pwcli --help
```

## Prerequisites

- The local project Postgres socket under `build/db` must be available
- `bash ./bin/in-env e2e` now shards the full suite across at most two app-server shards by default when no interactive or focused Playwright args are passed
- Each shard gets its own ephemeral database, dedicated app server, blob report, and test-results directory under `.devenv/e2e/<run-id>/`
- Parallel full-suite runs default to a single compiled app executable under the run artifact directory instead of multiple live-reload `RunDevServer` instances. This avoids GHCi/file-watcher/schema-codegen reload races against the shared working tree. Set `E2E_SERVER_MODE=dev` only when intentionally debugging the dev-server path.
- The wrapper merges shard blob reports into one HTML report and updates `.devenv/e2e/latest-report`
- Focused or interactive runs such as `--ui`, `--headed`, `--debug`, explicit file paths, `--project`, or `--grep` default back to a single shard unless `E2E_SHARDS` is set explicitly
- Playwright retries default to `1`; set `PLAYWRIGHT_RETRIES=0` through `bash ./bin/in-env env ...` when iterating on a known failure and you want the first failure immediately
- Test data is seeded automatically via `global-setup.ts` before tests run
- Before blaming Playwright, verify the app is actually serving the expected page:

```bash
tail -n 80 .devenv/e2e/server.log
ss -ltnp | rg '8000|8001|8002|8003'
```

If you see `Is compiling`, wait for the reload to finish or restart the managed dev server before rerunning tests.

## Writing New Tests

### File naming
Place test files in `e2e/` with the `.spec.ts` extension:
```
e2e/my-feature.spec.ts
```

### Basic template
```typescript
import { test, expect } from '@playwright/test';

test.describe('My Feature', () => {
    test('does something', async ({ page }) => {
        await page.goto('/MyPage');
        await expect(page.locator('body')).toContainText('Expected text');
    });
});
```

For pages that can briefly show the IHP compile screen during reloads, prefer the shared helpers:

```typescript
import { gotoWhenReady, loginAs, openRoster } from './test-helpers';

await gotoWhenReady(page, '/NewSession', '#email');
await loginAs(page, 'e2e-test@example.com', 'test-password-123');
await openRoster(page, { email: 'e2e-test@example.com', weekOffset: 1 });
```

`gotoWhenReady` retries the navigation until the expected selector appears instead of failing on the temporary `Is compiling` page. `loginAs` wraps the seeded login flow and waits for the post-login roster shell.
For privileged admin/support feature specs that are not directly testing passkeys, use `loginAsPrivilegedUserWithSeededPasskeySession` or `openAdminWithSeededPasskeySession`; reserve `loginAsPrivilegedUserWithFreshPasskey` and raw WebAuthn registration helpers for `passkeys.spec.ts` or passkey-specific coverage.
`gotoWhenReady` also retries transient `ERR_CONNECTION_REFUSED` startup races from the temporary E2E app server instead of failing immediately on the first `page.goto`.
`openRoster(page, ...)` is the shared helper for authenticated roster-grid specs. It defaults to the seeded venue admin (`e2e-admin@example.com`) and canonical roster-group fixture, preserves the current post-login grid when one is already visible, and otherwise resolves the current roster group before navigating to the canonical `ShowRosterWeek` route instead of assuming the `/RosterWeeks` landing page has already resolved to a concrete grid. New roster-grid specs should use `openRoster` unless they are explicitly testing authentication or initial roster routing.

For payroll/export coverage, the shared helpers in `e2e/test-helpers.ts` also provide:

- `gotoExports(page)` for the Admin > Exports accordion section
- `currentReportWeek(page)` for the default date-range inputs, which start on the current roster week
- `generatePayrollReport(page, reportName)` for the fixed export-generation cards
- `downloadExport(page, fileName)` for the recent-exports table
- `readDownloadText`, `listZipEntries`, and `readZipEntryText` for real file-content assertions
- `parseCsv(text)` for simple CSV sanity checks without duplicating parsing logic in specs

Exports are no longer a standalone page and report definitions are not managed through e2e flows. Use the fixed card labels (`Approved Timesheets CSV`, `Staff Hours CSV`, `Hourly Breakdown ZIP`, `Payroll Earnings CSV`) and assert the Admin export history table via `data-export-job-file`.

### UI behavior expectations worth covering
- For HTMX week pagers, assert both the shell swap and that no full page navigation occurred by preserving a `window` marker across clicks.
- For declarative live surfaces, cover the browser contract when behavior changes: the rendered owner has `data-live-update-surface`, legacy `data-live-update-owner` / `data-live-update-feature` attrs are absent, subscriptions are sent from the parsed config, matching HTMX requests receive `X-Live-Update-Client-Id`, resync refreshes the declared fragments, and focused-field protection defers only the protected fragment.
- For roster sidebar layout, prefer checking computed CSS (`position: sticky`, capped height, internal scroll container) over brittle pixel-perfect comparisons against neighboring panels.
- For responsive work, prefer structural assertions over screenshots first:
  - page-level horizontal overflow stays off the viewport
  - dense tables keep overflow contained inside `.table-responsive`
  - authenticated mobile nav expands and exposes the expected links
  - workflow dialogs fit inside the viewport width
- If a page does not expose a stable structural hook for the behavior you need to assert, add one in the view first. Prefer explicit ids or `data-*` attributes for cards, forms, rows, and status badges over selectors tied to Bootstrap utility classes or broad `body` text.

### Logging in within a test
```typescript
import { gotoWhenReady, loginAs } from './test-helpers';

test('authenticated feature', async ({ page }) => {
    await loginAs(page, 'e2e-test@example.com', 'test-password-123');

    // Now navigate to the authenticated page
    await gotoWhenReady(page, '/MyProtectedPage', 'body');
    // ...assertions...
});
```

## Test Data Convention

- All e2e test data uses the **`e2e-` prefix** on emails and identifiers
- The seeded manager is `e2e-test@example.com`, the seeded venue admin is `e2e-admin@example.com`, and the seeded worker is `e2e-worker@example.com`; all use password `test-password-123`
- Auth now also requires seeded `venues`, `venue_config`, and `venue_memberships` for the login user. A bare user row is not enough.
- The export/payroll fixture is seeded for the current report week in `e2e/fixtures/seed.sql`:
  - alpha venue has deterministic approved entries for the fixed Admin export formats
  - alpha venue has deterministic approved entries that produce visible CSV/ZIP content for those reports
  - beta venue has distinct payroll config for future cross-venue authorization coverage
- `global-teardown.ts` deletes all users with `email LIKE 'e2e-%'` after tests complete
- If a spec creates worker-owned leave or timesheet rows, teardown must delete those rows before deleting dependent `pay_config_snapshots` or user rows
- To add more fixture data, add SQL to `e2e/fixtures/seed.sql` using the `e2e-` prefix
- Use `ON CONFLICT DO UPDATE` for idempotency
- Prefer fixed UUIDs plus `ON CONFLICT DO UPDATE` so reruns stay deterministic
- Treat `e2e/fixtures/seed.sql` as durable fixture state: fixed-id venue rows can persist across runs, while teardown mainly cleans dynamic `e2e-%` users created during tests
- If a spec mutates fixed-id roster/week fixture rows, reset the mutable venue-scoped rows at the top of `e2e/fixtures/seed.sql` before reinserting them; do not rely on teardown of `e2e-%` users alone to restore roster state.
- Specs must not rely on cross-file ordering or cross-shard shared state. Treat each file as if it may run in a different isolated database from the rest of the suite.

## Assertion Style

- Prefer stable shell selectors such as `#roster-content`, `#timesheet-week-shell`, and `#leave-requests-content`
- Match the actual rendered copy, not seed helper names. Example: the roster grid renders staff as `Last, First`, while leave/timesheet views render `First Last`
- After login, wait for the destination shell selector as well as the URL because the post-login flow now resolves venue context before landing on roster pages
- Do not use `page.waitForTimeout(...)` to “let HTMX settle” in normal specs. Prefer asserting the concrete post-action contract instead: updated field value, fragment text, row count, conflict class, modal close, or URL/shell stability.
- Prefer stable view contracts like `data-report-slug`, `data-export-job-file`, or dedicated panel ids when asserting repeated list items. Avoid coupling specs to Bootstrap class combinations such as `.border.rounded.p-2.bg-white`, which are presentation details rather than behavior contracts.

## Timeout Policy

E2E timeouts are centralized in `e2e/timeouts.ts` and imported as `E2E_TIMEOUT`. Do not add numeric timeout literals to specs or `e2e/test-helpers.ts`; use the named timeout that matches the operation:

- `quick` for tiny retry sleeps inside helper loops
- `action` for local UI preconditions such as visible buttons, open accordions, and scroll assertions
- `assertion` for synchronous form results, generated rows, downloads, and ordinary DOM outcomes
- `navigation` for normal page transitions and login redirects
- `passkey` for WebAuthn registration or step-up completion
- `liveUpdate` for websocket/live-fragment propagation across pages
- `test` for ordinary whole-test budgets
- `slowTest` only for multi-page workflows that genuinely include several navigation, passkey, mail, or live-update steps

Tests should fail fast when the page is already in the wrong state. For example, assert that an accordion is expanded and the target card/button is visible with `E2E_TIMEOUT.action` before clicking, then wait for the concrete result with `E2E_TIMEOUT.assertion`. Do not rely on a whole-test timeout to catch a hidden locator.

## Live Load Profiling

Use the profile commands when investigating live-update scalability. They are profiling tools, not pass/fail regression gates, and write durable artifacts under `output/` for later agents to compare.

```bash
# Fast planner-only benchmark: no sockets, isolates expansion/planning cost.
bash ./bin/in-env profile-live-invalidation \
  --scopes=0,10,100,500,1000,2500,5000 \
  --iterations=100

# Real websocket fanout: isolated profile server and DB by default.
bash ./bin/in-env profile-live-load \
  --scenario=mixed-live \
  --subscribers=100 \
  --mutators=10 \
  --venues=4 \
  --weeks=3 \
  --warmup-ms=3000 \
  --hold-ms=12000 \
  --max-duration=35s

# Reuse a large seeded profile DB from a profile-load-suite run.
bash ./bin/in-env profile-live-load \
  --reuse-db \
  --db=app_profile_load_suite_<run-id> \
  --manifest=output/profile-load-suite/<run-id>/seed/manifest.json \
  --scenario=mixed-live \
  --subscribers=100 \
  --mutators=10
```

Read `output/profile-live-load/latest/live-profile.md` first. Its `Agent Snapshot` is intentionally compact: failed checks, mutation burst rate, invalidation delivery rate, own-invalidation coverage, slowest invalidation labels, and highest-fanout labels. Use it to decide where to dig before opening full logs.

For live-update bottlenecks, compare these signals in order:

- `Server Invalidation Labels`: high `Avg Plan` points at dependency matching/expansion; high `Avg Broadcast` with high subscribers points at fanout/transport; high fragments points at over-broad surface dependencies.
- `Mutation Timing By Surface`: high p95/max with low server invalidation time means the endpoint/business write is slow, not the live planner.
- `Rates`: mutation burst/sec and invalidation delivery/sec are more meaningful than total-run rates because setup/login/websocket warmup dominate elapsed time.
- `Failure Summary`: `profile_live_failed_mutations` identifies endpoint/request failures; `profile_live_missed_own_invalidations` identifies successful mutations whose actor did not receive an own invalidation. Treat a missed own invalidation only as a live-delivery issue when failed mutations are zero.
- `Counters By Surface`: missing own invalidations indicate an authorization/scope/dependency mismatch, source-client-id issue, websocket lifetime issue, or mutation failure; unexpected broad invalidations indicate a dependency or resource touch is too coarse.
- `server.log`: `[live-invalidation]` lines carry touched, active scopes, expanded resources, candidate/planning scopes, target fragments, subscribers, and stage timings.

The current useful mixed-live baseline is about `100` subscribers and `10` synchronized mutators. A heavier `200` subscriber / `25` mutator run has exposed occasional missed actor invalidations and one mutation failure; use that size as a stress probe, not as a required local gate.

## Operational Notes

- `dev-status` still reports the normal dev server on `:8000`; the E2E wrapper launches a separate temporary server on the next free IHP dev port and exports that URL to Playwright
- If Playwright keeps seeing stale compile output, check the listening IHP ports and the temporary server log:

```bash
ss -ltnp | rg '8000|8001|8002|8003'
tail -n 80 .devenv/e2e/server.log
```

## Playwright CLI

- Use `bash ./bin/in-env pwcli ...` for exploratory browser work: reproductions, selector discovery, ad hoc flows, and targeted screenshots before writing a durable spec
- Keep `bash ./bin/in-env e2e ...` as the canonical regression path for automated tests
- Keep `bash ./bin/in-env screenshot-page ...` for deterministic one-shot authenticated screenshots when you already know the target path and selector
- The wrapper currently pins `@playwright/cli` `0.1.4` via `npx` instead of adding it to `package.json`; this avoids mixing the repo's stable `@playwright/test` dependency with the CLI package's current alpha `playwright` runtime dependency
- `pwcli` sessions are repo-scoped through a local `.playwright/` workspace marker, so named sessions such as `ihp-manager` can be reused across separate `bash ./bin/in-env pwcli ...` calls
- Common first steps:

```bash
bash ./bin/in-env pwcli open http://127.0.0.1:8000 --headed
bash ./bin/in-env pwcli snapshot
bash ./bin/in-env pwcli screenshot
```

- Authentication state can be saved and restored with Playwright CLI's built-in storage commands:

```bash
bash ./bin/in-env pwcli state-save .devenv/playwright-cli/manager-state.json
bash ./bin/in-env pwcli state-load .devenv/playwright-cli/manager-state.json
```

- For authenticated `ihp-roster` pages, the recommended near-term pattern is:
  - run `bash ./bin/in-env seed-dev app` first when you want to browse the normal dev app with seeded manager/admin/worker/support accounts
  - create seeded dev auth state with `bash ./bin/in-env pwcli-auth-save manager` (or `worker`, `admin`, `support`)
  - `pwcli-auth-save` defaults to password `password123` for those dev accounts; this is intentionally different from the isolated `app_e2e` test password `test-password-123`
  - `pwcli-auth-save` verifies a concrete post-login page for the chosen role before writing the state file
  - open a pre-authenticated session with `bash ./bin/in-env pwcli-auth-open manager /RosterWeeks`
  - reuse the named session with `bash ./bin/in-env pwcli -s=ihp-manager snapshot`
  - if state is missing or stale, regenerate it explicitly instead of expecting `pwcli-auth-open` to do it implicitly

## Responsive Project Split

- `desktop-chromium` runs the existing desktop-oriented suite
- `mobile-chromium` and `tablet-chromium` run `e2e/mobile-experience.spec.ts`
- `mobile-chromium` and `tablet-chromium` also run `e2e/roster-mobile.spec.ts`
- `galaxy-s9-plus` runs the same mobile-focused specs with a 360px-wide Android profile
- `e2e/roster-mobile-screenshots.spec.ts` is opt-in via `E2E_INCLUDE_SCREENSHOTS=1`; prefer `bash ./bin/in-env e2e-roster-mobile-screenshots` during roster mobile UI work
- Keep mobile assertions focused on layout contracts and core flows, not on pixel-perfect matching
- If a spec assumes desktop-expanded navigation or sticky sidebars, keep it in the desktop suite unless the interaction is being made explicitly cross-device

## Roster Mobile Visual Diagnostics

Use `e2e-roster-mobile-screenshots` when changing roster layout, spacing, controls, picker behavior, or staff-panel placement on small screens. It runs the roster page through the mobile/tablet projects and attaches:

- full-page screenshots
- `#roster-week-shell` screenshots
- first editable row screenshots
- JSON layout metrics for viewport width, body/root scroll width, table overflow, staff panel, editable row, and overlay/picker regions

Use the normal `roster-mobile.spec.ts` assertions as the regression gate. Use the screenshot suite as the visual review path; do not add brittle pixel-perfect expectations while the mobile layout is still moving.

## Authenticated Screenshot Helper

Use `screenshot-page` when a page requires login/profile completion before rendering:

```bash
bash ./bin/in-env screenshot-page /RosterWeeks test-results/roster.png --selector '.roster-grid'
bash ./bin/in-env screenshot-page /RosterWeeks output/playwright/roster-pixel.png --device "Pixel 7" --selector '#roster-week-shell'
bash ./bin/in-env screenshot-page /RosterWeeks output/playwright/roster-grid.png --viewport 390x844 --clip-selector '.roster-slots-scroller' --selector '.roster-grid'
```

For the normal dev app, `screenshot-page` now defaults to the seeded dev manager login `dev-manager@example.com` / `password123`, so run `bash ./bin/in-env seed-dev app` first unless you pass explicit credentials. This is separate from the isolated `app_e2e` test accounts such as `e2e-test@example.com` / `test-password-123`.

Useful options:

- `--email` and `--password` to change credentials
- `--no-login` for public pages
- `--base-url` to target a non-default host
- `--login-path` and `--login-selector` when the auth entrypoint is not the default `/NewSession` + `#email`
- `--post-login-url-pattern` when the expected landing page is not one of `Dashboard|RosterWeeks|EditProfile`
- `--navigation-timeout-ms` and `--selector-timeout-ms` for cold IHP boots or slow compile/reload windows
- `--wait-ms` for delayed UI states
- `--device` for a Playwright device descriptor such as `Pixel 7`, `iPhone 13`, or `iPad Mini`
- `--viewport` for custom dimensions such as `360x740`
- `--clip-selector` for focused element screenshots such as `#roster-week-shell` or `.table-responsive`
- `--no-full-page` when you want only the viewport rather than a full-page capture

Recommended pattern for arbitrary authenticated screenshots:

```bash
bash ./bin/in-env screenshot-page /SomeProtectedPage test-results/page.png \
  --selector '#page-shell' \
  --navigation-timeout-ms 120000 \
  --selector-timeout-ms 120000
```

Use `--selector` for the real shell you care about, not just `body`. That keeps captures from succeeding on the temporary `Is compiling` screen or on half-rendered HTMX content.

## Common Selectors for IHP/Bootstrap Forms

| Element | Selector |
|---------|----------|
| Submit button | `button[type="submit"]` |
| Flash message | `.alert` |
| Flash success | `.alert-success` |
| Flash error | `.alert-danger` |
| Navigation link | `a:has-text("Link Text")` |
| Delete/logout button | `button:has-text("Delete")` or `button:has-text("Logout")` |

### Form field selectors

**Manually-specified IDs** (login form `Sessions/New.hs`):

| Field | Selector |
|-------|----------|
| Email | `#email` |
| Password | `#password` |

**`formFor`-generated IDs** follow the pattern `modelName_fieldName` (camelCase). For example, `formFor @User` with `textField #email` renders `id="user_email"`. Prefer selecting by `name` attribute to avoid ambiguity when multiple fields share a model:

| Field | Selector |
|-------|----------|
| Email (Users form) | `[name="email"]` |
| Password (Users form) | `[name="passwordHash"]` |
| Confirm password | `[name="passwordConfirmation"]` |

## Debugging

```bash
# Run with debug logging
DEBUG=pw:api bash ./bin/in-env e2e

# Run headed + slow motion
bash ./bin/in-env e2e --headed --slow-mo=500

# Generate and open a trace
bash ./bin/in-env e2e --trace on
bash ./bin/in-env playwright show-trace test-results/*/trace.zip
```
