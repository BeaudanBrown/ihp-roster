import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { loginAs, loginAsPrivilegedUserWithSeededPasskeySession } from './test-helpers';

test.describe('Authenticated header navigation', () => {
    test('venue admin header links navigate across roster, profile, timesheets, unavailability, and admin', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        await page.evaluate(() => {
            (window as Window & { __headerNavMarker?: string }).__headerNavMarker = 'before-profile';
        });

        await page.getByRole('link', { name: 'profile' }).click();
        await expect(page).toHaveURL(/EditProfile/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.getByRole('heading', { name: 'Profile', exact: true })).toBeVisible();
        await expect(page.locator('#firstName')).toBeVisible();
        await expect(page.evaluate(() => (window as Window & { __headerNavMarker?: string }).__headerNavMarker)).resolves.toBeUndefined();

        await page.getByRole('link', { name: 'timesheets' }).click();
        await expect(page).toHaveURL(/(Timesheets|ShowTimesheetWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        await page.getByRole('link', { name: 'unavailability' }).click();
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#leave-requests-content')).toBeVisible();

        await page.getByRole('link', { name: 'admin' }).click();
        await expect(page).toHaveURL(/Admin/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#admin-config-sections')).toBeVisible();
        await expect(page.getByRole('heading', { name: 'Roster Groups' }).first()).toBeVisible();

        await page.getByRole('link', { name: 'roster' }).click();
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    });

    test('worker header hides the unavailability link and uses profile as the unavailability entrypoint', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        await expect(page.getByRole('link', { name: 'roster' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'profile' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'unavailability' })).toHaveCount(0);
        await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);

        await page.getByRole('link', { name: 'profile' }).click();
        await expect(page).toHaveURL(/EditProfile/, { timeout: E2E_TIMEOUT.navigation });
        await expect(page.locator('#profile-content-fragment')).toBeVisible();

        const leaveSectionToggle = page.getByRole('button', { name: 'Unavailability' });
        if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
            await leaveSectionToggle.click();
        }

        await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
        await expect(page.locator('#profile-leave-requests-list-fragment')).toBeVisible();
    });
});
