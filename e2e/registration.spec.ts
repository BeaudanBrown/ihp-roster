import { test, expect } from '@playwright/test';

test.describe('Account Registration', () => {
    test('request access page explains invitation-only signup', async ({ page }) => {
        await page.goto('/NewUser');
        await expect(page.locator('body')).toContainText('Account creation is invitation-only');
        await expect(page.locator('body')).toContainText('Ask the founder or support team for an invitation link');
    });

    test('request access page does not expose the signup form without an invitation', async ({ page }) => {
        await page.goto('/NewUser');
        await expect(page.locator('[name="email"]')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Create Account' })).toHaveCount(0);
    });

    test('posting to create user without an invitation stays on request access', async ({ page }) => {
        await page.goto('/NewUser');
        await page.request.post('/CreateUser', {
            form: {
                email: 'e2e-register-no-invite@example.com',
                passwordHash: 'e2e-password-123',
                passwordConfirmation: 'e2e-password-123',
            },
        });
        await page.goto('/NewUser');
        await expect(page.locator('body')).toContainText('Account creation is invitation-only');
    });

    test('"Sign in" link navigates to login page', async ({ page }) => {
        await page.goto('/NewUser');
        await page.click('a:has-text("Sign in")');
        await expect(page).toHaveURL(/NewSession/);
    });

    test('"Request an invitation" link on login page navigates to request access', async ({ page }) => {
        await page.goto('/NewSession');
        await page.click('a:has-text("Request an invitation")');
        await expect(page).toHaveURL(/NewUser/);
    });
});
