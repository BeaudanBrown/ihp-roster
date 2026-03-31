import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

test.describe('Authentication', () => {
    test('login flow: sign in, view dashboard, logout', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');
        await expect(page.locator('body')).toContainText('Sign In');

        await page.fill('#email', 'e2e-test@example.com');
        await page.fill('#password', 'test-password-123');
        await page.click('button[type="submit"]');

        await expect(page).toHaveURL(/Dashboard/);
        await expect(page.locator('body')).toContainText('e2e-test@example.com');

        await page.getByRole('button', { name: /logout/i }).click();

        await expect(page).toHaveURL(/NewSession/);
    });

    test('dashboard requires authentication', async ({ page }) => {
        await gotoWhenReady(page, '/Dashboard', '#email');
        await expect(page).toHaveURL(/NewSession/);
    });

    test('login with wrong password shows error', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');
        await page.fill('#email', 'e2e-test@example.com');
        await page.fill('#password', 'wrong-password');
        await page.click('button[type="submit"]');

        await expect(page).toHaveURL(/.*Session.*/);
        await expect(page.locator('body')).toContainText(/[Ii]nvalid/);
    });
});
