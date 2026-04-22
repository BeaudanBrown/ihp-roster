import { test, expect } from '@playwright/test';
import { loginAs } from './test-helpers';

test.describe('Authenticated header navigation', () => {
    test('manager header links navigate across roster, profile, timesheets, leave, and admin', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        await page.evaluate(() => {
            window.__headerNavMarker = 'before-profile';
        });

        await page.getByRole('link', { name: 'profile' }).click();
        await expect(page).toHaveURL(/EditProfile/, { timeout: 60000 });
        await expect(page.getByRole('heading', { name: 'Profile', exact: true })).toBeVisible();
        await expect(page.locator('#firstName')).toBeVisible();
        await expect(page.evaluate(() => window.__headerNavMarker)).resolves.toBeUndefined();

        await page.getByRole('link', { name: 'timesheets' }).click();
        await expect(page).toHaveURL(/(Timesheets|ShowTimesheetWeek)/, { timeout: 60000 });
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        await page.getByRole('link', { name: 'leave' }).click();
        await expect(page).toHaveURL(/LeaveRequests/, { timeout: 60000 });
        await expect(page.locator('#leave-requests-content')).toBeVisible();

        await page.getByRole('link', { name: 'admin' }).click();
        await expect(page).toHaveURL(/Admin/, { timeout: 60000 });
        await expect(page.locator('#admin-config-sections')).toBeVisible();
        await expect(page.getByRole('heading', { name: 'Roster Groups' }).first()).toBeVisible();

        await page.getByRole('link', { name: 'roster' }).click();
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    });

    test('worker header hides the leave link and uses profile as the leave entrypoint', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        await expect(page.getByRole('link', { name: 'roster' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'profile' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'timesheets' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'leave' })).toHaveCount(0);
        await expect(page.getByRole('link', { name: 'admin' })).toHaveCount(0);

        await page.getByRole('link', { name: 'profile' }).click();
        await expect(page).toHaveURL(/EditProfile/, { timeout: 60000 });
        await expect(page.locator('#profile-content-fragment')).toBeVisible();

        const leaveSectionToggle = page.getByRole('button', { name: 'Leave Requests' });
        if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
            await leaveSectionToggle.click();
        }

        await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
        await expect(page.locator('#profile-leave-requests-list-fragment')).toBeVisible();
    });
});
