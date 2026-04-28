import { expect, test } from '@playwright/test';
import { gotoWhenReady, loginAsPrivilegedUserWithFreshPasskey, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

async function loginAsSuperAdmin(page: import('@playwright/test').Page) {
    await loginAsPrivilegedUserWithFreshPasskey(page, 'e2e-super-admin@example.com', 'test-password-123');
}

async function loginAsManager(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: 60000 });
}

test.describe('Super-admin venue switcher', () => {
    test('shows a venue switcher in the header and switches active venue', async ({ page }) => {
        await loginAsSuperAdmin(page);

        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');
        await expect(page.locator('#support-venue-switch')).toBeVisible();
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-alpha-venue');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');

        await page.selectOption('#support-venue-switch', { label: 'e2e-beta-venue' });
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: 60000 });

        await gotoWhenReady(page, '/Support', '#support-venue-switch');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');
    });

    test('does not show the venue switcher for ordinary venue admins', async ({ page }) => {
        await loginAsManager(page);

        await expect(page.locator('#support-venue-switch')).toHaveCount(0);
    });
});
