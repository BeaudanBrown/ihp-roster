import { test, expect } from '@playwright/test';
import { dialogMountDomAttr, passkeySetupPromptDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { enableVirtualPasskeyAuthenticator } from './support/passkeys';
import { dismissOptionalPasskeySetupPrompt, loginAs } from './support/session';
import { gotoWhenReady } from './support/runtime';

test.describe('Authentication', () => {
    test('login page does not expose public request access', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');

        await expect(page.locator('a', { hasText: 'Request an invitation' })).toHaveCount(0);
        await expect(page.locator('body')).not.toContainText('Need venue access?');
    });

    test('login flow: sign in, view the roster, logout', async ({ page }) => {
        // Navigate to login page
        await gotoWhenReady(page, '/NewSession', '#email');
        await expect(page.locator('body')).toContainText('Sign In');

        // Fill in credentials
        await page.fill('#email', 'e2e-test@example.com');
        await page.fill('#password', 'test-password-123');
        await page.click('button[type="submit"]');

        // Should redirect to the roster flow for the current venue
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator('.roster-week-nav-label')).toContainText('Week of');
        await expect(page.getByRole('banner').getByRole('link', { name: 'roster' })).toBeVisible();
        await dismissOptionalPasskeySetupPrompt(page);

        // Logout
        await page.click('a:has-text("logout"), button:has-text("logout")');

        // Should redirect to login page
        await expect(page).toHaveURL(/NewSession/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#email')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
    });

    test('cached login falls back to fresh credentials after logout invalidates its server session', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.click('a:has-text("logout"), button:has-text("logout")');
        await expect(page.locator('#email')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
    });

    test('optional prompt inspection waits for delayed document initialization', async ({ page }) => {
        await enableVirtualPasskeyAuthenticator(page);
        await gotoWhenReady(page, '/NewSession', '#email');
        await page.fill('#email', 'e2e-worker@example.com');
        await page.fill('#password', 'test-password-123');

        let delayedBundles = 0;
        await page.route(/\/app\.js(?:\?|$)/, async (route) => {
            delayedBundles += 1;
            // Fault injection, not a normal-flow settlement sleep: the shell is
            // already server-rendered while its dismissal listener is unavailable.
            await new Promise((resolve) => setTimeout(resolve, E2E_TIMEOUT.quick));
            await route.continue();
        });
        await page.click('button[type="submit"]', { noWaitAfter: true });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/);
        await expect(page.locator('#roster-content')).toBeVisible();
        const prompt = page.locator(`[${passkeySetupPromptDomAttr}]`).first();
        await expect(prompt.locator(`[${dialogMountDomAttr}]`)).toHaveCount(1);
        await dismissOptionalPasskeySetupPrompt(page);
        expect(delayedBundles).toBeGreaterThan(0);
        await expect(prompt.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0);

        await page.unroute(/\/app\.js(?:\?|$)/);
        await page.reload();
        await expect(prompt.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0);
    });

    test('valid restored cookies retain optional dismissal without another password mutation', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.context().clearCookies();
        // A fresh Page has no page-local init scripts from the first login.
        const restoredPage = await page.context().newPage();
        const passwordMutations: string[] = [];
        restoredPage.on('request', (request) => {
            if (request.method() === 'POST' && new URL(request.url()).pathname.includes('Session')) {
                passwordMutations.push(request.url());
            }
        });
        try {
            await loginAs(restoredPage, 'e2e-worker@example.com', 'test-password-123');
            await expect(restoredPage.locator('#roster-content')).toBeVisible();
            await expect(restoredPage.locator(`[${passkeySetupPromptDomAttr}] [${dialogMountDomAttr}]`)).toHaveCount(0);
            expect(passwordMutations).toEqual([]);
        } finally {
            await restoredPage.close();
        }
    });

    test('roster requires authentication', async ({ page }) => {
        // Try to access roster without being logged in
        await gotoWhenReady(page, '/RosterWeeks', '#email');

        // Should redirect to login page
        await expect(page).toHaveURL(/NewSession/);
    });

    test('login with wrong password shows error', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');
        await page.fill('#email', 'e2e-test@example.com');
        await page.fill('#password', 'wrong-password');
        await page.click('button[type="submit"]');

        // Should stay on login page with error
        await expect(page).toHaveURL(/.*Session.*/);
        await expect(page.locator('body')).toContainText(/[Ii]nvalid/);
    });
});
