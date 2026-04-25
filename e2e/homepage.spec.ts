import { test, expect } from '@playwright/test';

test.describe('Homepage', () => {
    test('loads the welcome page', async ({ page }) => {
        await page.goto('/');
        await expect(page).toHaveTitle(/Bepis/);
        await expect(page.locator('h1')).toContainText('Bepis');
        await expect(page.locator('body')).not.toContainText('Sign in with an invited account');
    });

    test('has sign in link', async ({ page }) => {
        await page.goto('/');
        const signInLink = page.locator('a', { hasText: 'Sign In' });
        await expect(signInLink).toBeVisible();
        await signInLink.click();
        await expect(page).toHaveURL(/NewSession/);
    });

    test('does not expose public request access', async ({ page }) => {
        await page.goto('/');
        await expect(page.locator('a', { hasText: 'Request Access' })).toHaveCount(0);
    });
});
