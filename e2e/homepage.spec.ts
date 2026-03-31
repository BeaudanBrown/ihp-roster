import { test, expect } from '@playwright/test';

test.describe('Homepage', () => {
    test('loads the welcome page', async ({ page }) => {
        await page.goto('/');
        await expect(page).toHaveTitle(/Welcome/);
        await expect(page.locator('body')).toContainText('Sign in with an invited account');
    });

    test('has sign in link', async ({ page }) => {
        await page.goto('/');
        const signInLink = page.locator('a', { hasText: 'Sign In' });
        await expect(signInLink).toBeVisible();
        await signInLink.click();
        await expect(page).toHaveURL(/NewSession/);
    });

    test('has request access link', async ({ page }) => {
        await page.goto('/');
        const requestAccessLink = page.locator('a', { hasText: 'Request Access' });
        await expect(requestAccessLink).toBeVisible();
        await requestAccessLink.click();
        await expect(page).toHaveURL(/NewUser/);
        await expect(page.locator('body')).toContainText('Ask the founder or support team for an invitation link');
    });
});
