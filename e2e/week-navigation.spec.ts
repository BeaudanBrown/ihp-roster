import { test, expect } from '@playwright/test';
import { timesheetsTimesheetSidePanelTabDomAttr } from '../frontend/ts/generated/contracts';
import { gotoWhenReady, loginAs, openRoster, openTimesheetSettings, waitForRosterWeekShell } from './test-helpers';

test.describe('Week navigation', () => {
    test('roster week pager swaps the shell without a full page navigation', async ({ page }) => {
        await openRoster(page, { email: 'e2e-test@example.com' });

        await page.evaluate(() => {
            window.__rosterWeekNavMarker = 'still-here';
        });

        const initialShell = await page.locator('#roster-week-shell').evaluate((el) => el.outerHTML);

        await page.getByRole('link', { name: 'Next week' }).click();
        await expect(page).toHaveURL(/ShowRosterWindow/);
        await waitForRosterWeekShell(page);

        const marker = await page.evaluate(() => window.__rosterWeekNavMarker);
        expect(marker).toBe('still-here');

        const nextShell = await page.locator('#roster-week-shell').evaluate((el) => el.outerHTML);
        expect(nextShell).not.toBe(initialShell);
    });

    test('timesheet week pager swaps the shell without a full page navigation', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        await page.evaluate(() => {
            window.__timesheetWeekNavMarker = 'still-here';
        });

        const initialShell = await page.locator('#timesheet-week-shell').evaluate((el) => el.outerHTML);
        await openTimesheetSettings(page);

        await page.getByRole('link', { name: '>' }).click();
        await expect(page).toHaveURL(/ShowTimesheetWindow/);
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        const marker = await page.evaluate(() => window.__timesheetWeekNavMarker);
        expect(marker).toBe('still-here');

        const nextShell = await page.locator('#timesheet-week-shell').evaluate((el) => el.outerHTML);
        expect(nextShell).not.toBe(initialShell);
        await expect(page.locator(`[${timesheetsTimesheetSidePanelTabDomAttr}="settings"]`)).toHaveAttribute('aria-selected', 'true');
    });
});
