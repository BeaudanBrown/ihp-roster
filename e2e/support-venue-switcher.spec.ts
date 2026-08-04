import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    defaultE2ERosterGroupId,
    gotoWhenReady,
    loginAsPrivilegedUserWithSeededPasskeySession,
    openRoster,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

async function loginAsSuperAdmin(page: import('@playwright/test').Page) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-super-admin@example.com', 'test-password-123');
}

async function loginAsManager(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
}

test.describe('Super-admin venue and user switchers', () => {
    test('impersonates and immediately exits from the desktop header without exposing emails', async ({ page }) => {
        await loginAsSuperAdmin(page);
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });

        const userSwitcher = page.locator('#support-impersonation-user');
        await expect(userSwitcher).toBeVisible();
        await expect(userSwitcher).toContainText('Super admin');
        await expect(userSwitcher).toContainText('Alpha — Worker');
        await expect(userSwitcher).not.toContainText('@');

        await userSwitcher.selectOption({ label: 'Alpha — Worker' });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');
        await expect(page.getByRole('link', { name: 'support', exact: true })).toBeVisible();
        await expect(page.getByRole('link', { name: 'admin', exact: true })).toHaveCount(0);

        await page.locator('#support-impersonation-user').selectOption({ label: 'Super admin' });
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Super admin');
        await expect(page.getByRole('link', { name: 'support', exact: true })).toBeVisible();
    });

    test('shows a venue switcher in the header and switches active venue', async ({ page }) => {
        await loginAsSuperAdmin(page);

        await gotoWhenReady(page, '/LeaveRequests', '#leave-requests-content');
        await expect(page.locator('#support-venue-switch')).toBeVisible();
        await expect(page.locator('label[for="support-venue-switch"]')).toHaveText('Support venue');
        await expect(page.locator('label[for="support-venue-switch"]')).toBeVisible();
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-alpha-venue');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');

        await page.selectOption('#support-venue-switch', { label: 'e2e-beta-venue' });
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#leave-requests-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('body')).not.toContainText(/FORBIDDEN/i);

        await gotoWhenReady(page, '/Support', '#support-venue-switch');
        await expect(page.locator('#support-venue-switch')).toContainText('e2e-beta-venue');
    });

    test('switching from a venue-specific roster URL opens the new venue roster', async ({ page }) => {
        await loginAsSuperAdmin(page);
        await openRoster(page, {
            email: 'e2e-super-admin@example.com',
            password: 'test-password-123',
            ensureEditable: false,
            useCurrentSession: true,
        });

        await page.selectOption('#support-impersonation-user', { label: 'Alpha — Worker' });
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Alpha — Worker');

        await page.selectOption('#support-venue-switch', { label: 'e2e-beta-venue' });

        await expect(page).toHaveURL(
            (url) =>
                url.pathname === '/ShowRosterWeek'
                && url.searchParams.has('rosterGroupId')
                && url.searchParams.get('rosterGroupId') !== defaultE2ERosterGroupId,
            { timeout: E2E_TIMEOUT.navigation },
        );
        await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#support-venue-switch option:checked')).toHaveText('e2e-beta-venue');
        await expect(page.locator('#support-impersonation-user option:checked')).toHaveText('Super admin');
        await expect(page.locator('body')).not.toContainText(/FORBIDDEN/i);
    });

    test('does not show the venue switcher for ordinary venue admins', async ({ page }) => {
        await loginAsManager(page);

        await expect(page.locator('#support-venue-switch')).toHaveCount(0);
        await expect(page.locator('#support-impersonation-user')).toHaveCount(0);
    });
});
