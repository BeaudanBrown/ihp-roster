import { test, expect } from '@playwright/test';

async function login(page) {
    await page.goto('/NewSession');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);
}

async function ensureRosterDraft(page) {
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);

    const createDraftButton = page.locator('button:has-text("Create Draft Roster")');
    if (await createDraftButton.isVisible()) {
        await createDraftButton.click();
    }

    await expect(page.locator('#roster-week-shell')).toBeVisible();
    await expect(page.locator('#roster-content')).toBeVisible();
}

test.describe('Week navigation', () => {
    test('roster week pager swaps the shell without a full page navigation', async ({ page }) => {
        await login(page);
        await ensureRosterDraft(page);

        await page.evaluate(() => {
            window.__rosterWeekNavMarker = 'still-here';
        });

        const initialShell = await page.locator('#roster-week-shell').evaluate((el) => el.outerHTML);

        await page.getByRole('link', { name: 'Next week' }).click();
        await expect(page).toHaveURL(/ShowRosterWeek/);
        await expect(page.locator('#roster-week-shell')).toBeVisible();

        const marker = await page.evaluate(() => window.__rosterWeekNavMarker);
        expect(marker).toBe('still-here');

        const nextShell = await page.locator('#roster-week-shell').evaluate((el) => el.outerHTML);
        expect(nextShell).not.toBe(initialShell);
    });

    test('timesheet week pager swaps the shell without a full page navigation', async ({ page }) => {
        await login(page);
        await page.goto('/Timesheets');
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        await page.evaluate(() => {
            window.__timesheetWeekNavMarker = 'still-here';
        });

        const initialShell = await page.locator('#timesheet-week-shell').evaluate((el) => el.outerHTML);

        await page.getByRole('link', { name: '>' }).click();
        await expect(page).toHaveURL(/ShowTimesheetWeek/);
        await expect(page.locator('#timesheet-week-shell')).toBeVisible();

        const marker = await page.evaluate(() => window.__timesheetWeekNavMarker);
        expect(marker).toBe('still-here');

        const nextShell = await page.locator('#timesheet-week-shell').evaluate((el) => el.outerHTML);
        expect(nextShell).not.toBe(initialShell);
    });
});
