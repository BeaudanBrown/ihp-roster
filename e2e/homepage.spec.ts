import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './test-helpers';

test.describe('Homepage', () => {
    test('loads the welcome page', async ({ page }) => {
        await gotoWhenReady(page, '/', 'a[href="/NewSession"]');
        await expect(page).toHaveTitle(/Welcome/);
        await expect(page.locator('body')).toContainText('Sign in to your account');
    });

    test('has sign in link', async ({ page }) => {
        await gotoWhenReady(page, '/', 'a[href="/NewSession"]');
        const signInLink = page.locator('a', { hasText: 'Sign In' });
        await expect(signInLink).toBeVisible();
        await signInLink.click();
        await expect(page).toHaveURL(/NewSession/);
    });

    test('has create account link', async ({ page }) => {
        await gotoWhenReady(page, '/', 'a[href="/NewUser"]');
        const createLink = page.locator('a', { hasText: 'Create Account' });
        await expect(createLink).toBeVisible();
        await createLink.click();
        await expect(page).toHaveURL(/NewUser/);
    });
});
