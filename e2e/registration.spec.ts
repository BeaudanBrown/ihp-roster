import { test, expect } from '@playwright/test';

test.describe('Account Registration', () => {
    test('successful account creation redirects to login', async ({ page }) => {
        const email = `e2e-register-success-${Date.now()}@example.com`;

        await page.goto('/NewUser');
        await page.fill('[name="email"]', email);
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'e2e-password-123');
        await page.click('button[type="submit"]');

        // Should redirect to login with success flash
        await expect(page).toHaveURL(/NewSession/);
        await expect(page.locator('#toast-overlay-mount')).toContainText('Account created! Please log in.');
    });

    test('password mismatch shows validation error', async ({ page }) => {
        await page.goto('/NewUser');
        await page.fill('[name="email"]', 'e2e-register-mismatch@example.com');
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'different-password');
        await page.click('button[type="submit"]');

        // Should stay on registration page with an error
        await expect(page).toHaveURL(/NewUser|CreateUser/);
        await expect(page.locator('body')).toContainText("Passwords don't match");
    });

    test('duplicate email shows validation error', async ({ page }) => {
        await page.goto('/NewUser');
        // e2e-test@example.com is seeded and already exists
        await page.fill('[name="email"]', 'e2e-test@example.com');
        await page.fill('[name="passwordHash"]', 'e2e-password-123');
        await page.fill('[name="passwordConfirmation"]', 'e2e-password-123');
        await page.click('button[type="submit"]');

        // Should stay on registration page with a uniqueness error
        await expect(page).toHaveURL(/NewUser|CreateUser/);
        await expect(page.locator('body')).toContainText(/already|taken|exists/i);
    });

    test('"Sign in" link navigates to login page', async ({ page }) => {
        await page.goto('/NewUser');
        await page.click('a:has-text("Sign in")');
        await expect(page).toHaveURL(/NewSession/);
    });

    test('"Create one" link on login page navigates to registration', async ({ page }) => {
        await page.goto('/NewSession');
        await page.click('a:has-text("Create one")');
        await expect(page).toHaveURL(/NewUser/);
    });
});
