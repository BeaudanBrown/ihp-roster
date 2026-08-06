import { test, expect } from '@playwright/test';
import {
    defaultE2ERosterGroupId,
    E2E_TIMEOUT,
    openRoster,
    openRosterSettings,
    runSql,
} from './test-helpers';

test.describe('Roster notification workflow', () => {
    test('opens confirmation in place for managers and stays hidden from workers', async ({ browser, page }, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'Role-specific notification workflow is covered once on desktop.');
        await openRoster(page);
        const weekOffset = Number.parseInt(new URL(page.url()).searchParams.get('weekOffset') ?? '0', 10);
        runSql(`UPDATE roster_weeks SET is_live = TRUE WHERE roster_group_id = '${defaultE2ERosterGroupId}' AND week_offset = ${weekOffset};`);
        try {
            await page.reload();
            await expect(page.locator('#roster-week-shell')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await openRosterSettings(page);
            const emailRoster = page.locator('#roster-email-button');
            await expect(emailRoster).toBeVisible();
            await expect(emailRoster).toBeEnabled();
            const originalUrl = page.url();
            await page.evaluate(() => { (window as Window & { __notificationMarker?: string }).__notificationMarker = 'preserved'; });
            await emailRoster.click();
            const dialog = page.getByRole('dialog', { name: 'Email roster' });
            await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await expect(dialog).toContainText('Recipients');
            expect(page.url()).toBe(originalUrl);
            expect(await page.evaluate(() => (window as Window & { __notificationMarker?: string }).__notificationMarker)).toBe('preserved');

            const workerContext = await browser.newContext();
            const workerPage = await workerContext.newPage();
            try {
                await openRoster(workerPage, {
                    email: 'e2e-worker@example.com',
                    weekOffset,
                    ensureDraft: false,
                    ensureEditable: false,
                });
                await expect(workerPage.locator('#roster-email-button')).toHaveCount(0);
            } finally {
                await workerContext.close();
            }
        } finally {
            runSql(`UPDATE roster_weeks SET is_live = FALSE WHERE roster_group_id = '${defaultE2ERosterGroupId}' AND week_offset = ${weekOffset};`);
        }
    });
});
