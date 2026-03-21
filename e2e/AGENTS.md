# E2E Testing — Agent Guide

## Running Tests

All commands require `bash ./bin/in-env` (or an already active devenv shell). Do not rely on bare `npx playwright ...` in Loom or other automation contexts; the repo wrapper resolves the repo-local Playwright test CLI inside the dev shell so the runner matches the `@playwright/test` package imported by the specs.

```bash
# Run all e2e tests
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

# View the last test report
bash ./bin/in-env e2e-report
```

## Prerequisites

- The local project Postgres socket under `build/db` must be available
- `bash ./bin/in-env e2e` resets the isolated `app_test` database, launches a dedicated app server on the next free local IHP dev port, and points Playwright at that server
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

### UI behavior expectations worth covering
- For HTMX week pagers, assert both the shell swap and that no full page navigation occurred by preserving a `window` marker across clicks.
- For roster sidebar layout, prefer checking computed CSS (`position: sticky`, capped height, internal scroll container) over brittle pixel-perfect comparisons against neighboring panels.

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
- `global-teardown.ts` deletes all users with `email LIKE 'e2e-%'` after tests complete
- If a spec creates worker-owned leave or timesheet rows, teardown must delete those rows before deleting dependent `pay_config_snapshots` or user rows
- To add more fixture data, add SQL to `e2e/fixtures/seed.sql` using the `e2e-` prefix
- Use `ON CONFLICT DO UPDATE` for idempotency
- Prefer fixed UUIDs plus `ON CONFLICT DO UPDATE` so reruns stay deterministic
- Treat `e2e/fixtures/seed.sql` as durable fixture state: fixed-id venue rows can persist across runs, while teardown mainly cleans dynamic `e2e-%` users created during tests
- If a spec mutates fixed-id roster/week fixture rows, reset the mutable venue-scoped rows at the top of `e2e/fixtures/seed.sql` before reinserting them; do not rely on teardown of `e2e-%` users alone to restore roster state.

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

## Authenticated Screenshot Helper

Use `screenshot-page` when a page requires login/profile completion before rendering:

```bash
bash ./bin/in-env screenshot-page /RosterWeeks test-results/roster.png --selector 'table.roster-grid'
```

Useful options:

- `--email` and `--password` to change credentials
- `--no-login` for public pages
- `--base-url` to target a non-default host
- `--wait-ms` for delayed UI states

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
