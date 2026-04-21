# E2E Testing — Agent Guide

## Running Tests

All commands require `bash ./bin/in-env` (or an already active devenv shell). Do not rely on bare `npx playwright ...` in Loom or other automation contexts; the repo wrapper resolves the repo-local Playwright test CLI inside the dev shell so the runner matches the `@playwright/test` package imported by the specs.

```bash
# Run the full e2e suite, auto-sharded across local cores
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
bash ./bin/in-env screenshot-page /RosterWeeks roster.png --selector 'table.roster-grid'

# Same flow, but tolerant of cold IHP boot/compile time
bash ./bin/in-env screenshot-page /RosterWeeks roster.png \
  --selector 'table.roster-grid' \
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

# Use Playwright CLI for exploratory browser automation
bash ./bin/in-env pwcli --help
```

## Prerequisites

- The local project Postgres socket under `build/db` must be available
- `bash ./bin/in-env e2e` now shards the full suite across local cores when no interactive or focused Playwright args are passed
- Each shard gets its own ephemeral database, dedicated app server, blob report, and test-results directory under `.devenv/e2e/<run-id>/`
- The wrapper merges shard blob reports into one HTML report and updates `.devenv/e2e/latest-report`
- Focused or interactive runs such as `--ui`, `--headed`, `--debug`, explicit file paths, `--project`, or `--grep` default back to a single shard unless `E2E_SHARDS` is set explicitly
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
import { gotoWhenReady, loginAs } from './test-helpers';

await gotoWhenReady(page, '/NewSession', '#email');
await loginAs(page, 'e2e-test@example.com', 'test-password-123');
```

`gotoWhenReady` retries the navigation until the expected selector appears instead of failing on the temporary `Is compiling` page. `loginAs` wraps the seeded login flow and waits for the post-login roster shell.
`gotoWhenReady` also retries transient `ERR_CONNECTION_REFUSED` startup races from the temporary E2E app server instead of failing immediately on the first `page.goto`.

For payroll/export coverage, the shared helpers in `e2e/test-helpers.ts` also provide:

- `gotoExports(page)` for the exports-page shell
- `currentReportWeek(page)` and `shiftExportWeek(page, ...)` for report-week navigation
- `generatePayrollReport(page, reportName)` for the native report-generation forms
- `downloadExport(page, fileName)` for the recent-exports table
- `readDownloadText`, `listZipEntries`, and `readZipEntryText` for real file-content assertions
- `parseCsv(text)` for simple CSV sanity checks without duplicating parsing logic in specs

### UI behavior expectations worth covering
- For HTMX week pagers, assert both the shell swap and that no full page navigation occurred by preserving a `window` marker across clicks.
- For roster sidebar layout, prefer checking computed CSS (`position: sticky`, capped height, internal scroll container) over brittle pixel-perfect comparisons against neighboring panels.
- For responsive work, prefer structural assertions over screenshots first:
  - page-level horizontal overflow stays off the viewport
  - dense tables keep overflow contained inside `.table-responsive`
  - authenticated mobile nav expands and exposes the expected links
  - workflow dialogs fit inside the viewport width

### Logging in within a test
```typescript
import { gotoWhenReady } from './test-helpers';

test('authenticated feature', async ({ page }) => {
    // Login with the seeded test user
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });

    // Now navigate to the authenticated page
    await page.goto('/MyProtectedPage');
    // ...assertions...
});
```

## Test Data Convention

- All e2e test data uses the **`e2e-` prefix** on emails and identifiers
- The seeded manager is `e2e-test@example.com`, the seeded venue admin is `e2e-admin@example.com`, and the seeded worker is `e2e-worker@example.com`; all use password `test-password-123`
- Auth now also requires seeded `venues`, `venue_config`, and `venue_memberships` for the login user. A bare user row is not enough.
- The export/payroll fixture is seeded for the current report week in `e2e/fixtures/seed.sql`:
  - alpha venue has active `wage`, `staff_hours`, and `kitchen` report definitions
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
bash ./bin/in-env screenshot-page /RosterWeeks test-results/roster.png --selector 'table.roster-grid'
bash ./bin/in-env screenshot-page /RosterWeeks output/playwright/roster-pixel.png --device "Pixel 7" --selector '#roster-week-shell'
bash ./bin/in-env screenshot-page /RosterWeeks output/playwright/roster-table.png --viewport 390x844 --clip-selector '.table-responsive' --selector 'table.roster-grid'
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
