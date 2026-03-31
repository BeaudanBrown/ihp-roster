# E2E Testing — Agent Guide

## Running Tests

Use `bash ./bin/in-env` as the default entrypoint for automation and worktrees. It resolves the repo-local dev shell even when `.envrc` is absent.

```bash
bash ./bin/in-env e2e
bash ./bin/in-env e2e e2e/auth.spec.ts
bash ./bin/in-env e2e --headed
bash ./bin/in-env e2e --ui
bash ./bin/in-env screenshot http://localhost:8000/MyPage output.png
bash ./bin/in-env screenshot-page /SomePage output.png
bash ./bin/in-env e2e-report
```

## Prerequisites
- The local Postgres socket at `build/db` must be available
- `bash ./bin/in-env e2e` rebuilds the isolated `app_test` database, builds `build/bin/RunUnoptimizedProdServer`, and launches it on a temporary port automatically when `BASE_URL` is not already set
- Seed data is prepared by `global-setup.ts`

Before debugging Playwright, confirm the app is serving the expected page:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-app-port
curl -s "http://127.0.0.1:$(bash ./bin/in-env dev-app-port)/NewSession" | rg 'id="email"|Is compiling'
```

If you see `Is compiling`, wait or restart the managed server.

## Writing New Tests

### File naming
Place tests in `e2e/` with the `.spec.ts` suffix.

### Basic template

```typescript
import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

test.describe('My Feature', () => {
    test('does something', async ({ page }) => {
        await gotoWhenReady(page, '/MyPage', '#my-page-shell');
        await expect(page.locator('body')).toContainText('Expected text');
    });
});
```

Prefer the shared helpers in `e2e/test-helpers.ts` for startup races, login, and live-update state.

### Logging in within a test

```typescript
import { loginAs } from './test-helpers';

test('authenticated feature', async ({ page }) => {
    await loginAs(page, 'e2e-test@example.com', 'test-password-123');
    await expect(page).toHaveURL(/(Dashboard|MyPage|Show)/);
});
```

## Test Data Convention
- Use the `e2e-` prefix for durable test data
- The seeded test user is `e2e-test@example.com` / `test-password-123`
- `global-teardown.ts` deletes rows associated with `e2e-` users after runs
- Prefer fixed identifiers plus `ON CONFLICT DO UPDATE` in seed SQL for deterministic reruns

## Assertion Style
- Prefer stable shell selectors over brittle visual assumptions
- Match the rendered copy rather than helper names
- After login, wait for both the destination URL and a page-specific selector when the flow includes redirects or setup steps

## Operational Notes
- The isolated `e2e` wrapper uses the compiled server path, so browser automation should not see the dev compile screen unless you override `BASE_URL`
- `dev-status` only proves something is answering on the dev port; it does not guarantee the managed dev server is past the compile screen
- If tests keep seeing stale output, stop and restart the managed server with:

```bash
bash ./bin/in-env dev-stop
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
```

## Authenticated Screenshot Helper
Use `screenshot-page` for pages that require login or setup before rendering:

```bash
bash ./bin/in-env screenshot-page /SomeProtectedPage test-results/page.png
```

Useful options:
- `--email`
- `--password`
- `--no-login`
- `--base-url`
- `--selector`
- `--wait-ms`

## Common Selectors
- Submit button: `button[type="submit"]`
- Toast: `.app-toast`
- Dialog overlay: `[data-dialog-overlay="true"]`
- Logout button: `button:has-text("logout")`
- Login email: `#email`
- Login password: `#password`

For `formFor`-generated forms, prefer `[name="fieldName"]` selectors.

## Debugging

```bash
DEBUG=pw:api bash ./bin/in-env e2e
bash ./bin/in-env e2e --headed --slow-mo=500
bash ./bin/in-env e2e --trace on
npx playwright show-trace test-results/*/trace.zip
```
