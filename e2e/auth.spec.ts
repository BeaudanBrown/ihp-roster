import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { dismissOptionalPasskeySetupPrompt, gotoWhenReady } from './test-helpers';

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
