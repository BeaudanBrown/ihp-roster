import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

test.describe('Authentication', () => {
    test('auth link navigation updates the page body', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');

        await page.click('a:has-text("Request an invitation")');

        await expect(page).toHaveURL(/NewUser/, { timeout: 60000 });
        await expect(page.locator('body')).toContainText('Invitation Required');
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
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
        await expect(page.locator('#roster-content')).toBeVisible({ timeout: 60000 });
        await expect(page.locator('body')).toContainText('Schedule');

        // Logout
        await page.click('a:has-text("logout"), button:has-text("logout")');

        // Should redirect to login page
        await expect(page).toHaveURL(/NewSession/, { timeout: 60000 });
        await expect(page.locator('#email')).toBeVisible({ timeout: 60000 });
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
