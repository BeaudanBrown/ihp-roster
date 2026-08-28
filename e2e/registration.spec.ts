import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';

test.describe('Account Registration', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('request access page explains invitation-only signup', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', 'body');
        await expect(page.locator('body')).toContainText('Invitation Required');
        await expect(page.locator('body')).toContainText('Ask the founder or support team for an invitation link');
    });

    test('request access page does not expose the signup form without an invitation', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', 'body');
        await expect(page.locator('[name="email"]')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Create Account' })).toHaveCount(0);
    });

    test('posting to create user without an invitation stays on request access', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', 'body');
        await page.request.post('/CreateUser', {
            form: {
                email: 'e2e-register-no-invite@example.com',
                passwordHash: 'e2e-password-123',
                passwordConfirmation: 'e2e-password-123',
            },
        });
        await gotoWhenReady(page, '/NewUser', 'body');
        await expect(page.locator('body')).toContainText('Invitation Required');
    });

    test('"Sign in" link navigates to login page', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', 'body');
        await page.click('a:has-text("Sign in")');
        await expect(page).toHaveURL(/NewSession/);
    });

    test('login page does not link to request access', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', 'body');
        await expect(page.locator('a', { hasText: 'Request an invitation' })).toHaveCount(0);
    });
});
