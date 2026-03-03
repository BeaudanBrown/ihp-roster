# E2E Testing — Agent Guide

## Running Tests

All commands require `direnv exec .` unless you are already inside an activated direnv shell.

```bash
direnv exec . e2e
direnv exec . e2e e2e/auth.spec.ts
direnv exec . e2e --headed
direnv exec . e2e --ui
direnv exec . screenshot http://localhost:8000/MyPage output.png
direnv exec . screenshot-page /SomePage output.png
direnv exec . e2e-report
```

## Prerequisites
- `devenv up` or the managed dev server must be running
- `make db` must have been run at least once
- Seed data is prepared by `global-setup.ts`

Before debugging Playwright, confirm the app is serving the expected page:

```bash
curl -s http://localhost:8000/NewSession | rg 'id="email"|Is compiling'
```

If you see `Is compiling`, wait or restart the managed server.

## Writing New Tests

### File naming
Place tests in `e2e/` with the `.spec.ts` suffix.

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

If a page may briefly show the IHP compile screen, prefer the shared `gotoWhenReady` helper when available.

### Logging in within a test

```typescript
test('authenticated feature', async ({ page }) => {
    await page.goto('/NewSession');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
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
- `dev-status` only proves something is answering on the dev port; it does not guarantee the app is past the compile screen
- If tests keep seeing stale output, stop and restart the managed server with:

```bash
direnv exec . dev-stop
direnv exec . dev-start
direnv exec . dev-wait
```

## Authenticated Screenshot Helper
Use `screenshot-page` for pages that require login or setup before rendering:

```bash
direnv exec . screenshot-page /SomeProtectedPage test-results/page.png
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
- Flash message: `.alert`
- Toast: `.app-toast`
- Delete/logout button: `.js-delete`
- Login email: `#email`
- Login password: `#password`

For `formFor`-generated forms, prefer `[name="fieldName"]` selectors.

## Debugging

```bash
DEBUG=pw:api direnv exec . e2e
direnv exec . e2e --headed --slow-mo=500
direnv exec . e2e --trace on
npx playwright show-trace test-results/*/trace.zip
```
