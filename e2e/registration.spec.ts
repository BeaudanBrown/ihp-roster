import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

test.describe('Account Registration', () => {
    test('successful account creation redirects to login', async ({ page }) => {
        const email = `e2e-register-success-${Date.now()}@example.com`;

        await gotoWhenReady(page, '/NewUser', '[name="email"]');
        await page.fill('[name="email"]', email);
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'e2e-password-123');
        await page.click('button[type="submit"]');

        await expect(page).toHaveURL(/NewSession/);
        await expect(page.locator('#toast-overlay-mount')).toContainText('Account created! Please log in.');
    });

    test('password mismatch shows validation error', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', '[name="email"]');
        await page.fill('[name="email"]', 'e2e-register-mismatch@example.com');
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'different-password');
        await page.click('button[type="submit"]');

        await expect(page).toHaveURL(/NewUser|CreateUser/);
        await expect(page.locator('body')).toContainText("Passwords don't match");
    });

    test('duplicate email shows validation error', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', '[name="email"]');
        await page.fill('[name="email"]', 'e2e-test@example.com');
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'e2e-password-123');
        await page.click('button[type="submit"]');

        await expect(page).toHaveURL(/NewUser|CreateUser/);
        await expect(page.locator('body')).toContainText(/already|taken|exists/i);
    });

    test('"Sign in" link navigates to login page', async ({ page }) => {
        await gotoWhenReady(page, '/NewUser', 'a[href="/NewSession"]');
        await page.click('a:has-text("Sign in")');
        await expect(page).toHaveURL(/NewSession/);
    });

    test('"Create one" link on login page navigates to registration', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', 'a[href="/NewUser"]');
        await page.click('a:has-text("Create one")');
        await expect(page).toHaveURL(/NewUser/);
    });
});
