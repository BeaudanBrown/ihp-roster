import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAs } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster week overview', () => {
    test('shows month data for another week and counts assigned shifts correctly', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');
        await expect(page.locator('[data-week-overview-fragment-mount="true"] [data-week-overview-loaded="true"]')).toHaveCount(1);

        await page.getByRole('button', { name: 'Open roster week overview' }).click();

        const overviewMenu = page.locator('.roster-week-overview-menu.show');
        await expect(overviewMenu).toBeVisible();

        const nextWeekDay = overviewMenu.locator('[data-week-overview-day="true"][data-week-overview-assigned="2"]');
        await expect(nextWeekDay).toBeVisible();
        const selectedDayLabel = await nextWeekDay.getAttribute('data-week-overview-label');
        const targetWeekUrl = await nextWeekDay.getAttribute('data-week-overview-url');
        await nextWeekDay.click();

        await expect(overviewMenu.locator('[data-week-overview-selected-label="true"]')).toHaveText(selectedDayLabel ?? '');
        await expect(overviewMenu.locator('[data-week-overview-leave-value="true"]')).toHaveText('1');
        await expect(overviewMenu.locator('[data-week-overview-assigned-value="true"]')).toHaveText('2');
        await expect(overviewMenu.locator('[data-week-overview-hours-value="true"]')).toHaveText('8h');

        const goLink = overviewMenu.locator('[data-week-overview-go-link="true"]');
        await expect(goLink).toHaveAttribute('href', targetWeekUrl ?? '');
        await goLink.click();

        await expect(page).toHaveURL(/weekOffset=1/);
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    });

    test('exports the live roster as a png from the roster actions menu', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');

        await page.getByRole('button', { name: 'Roster actions' }).click();
        const exportButton = page.getByRole('button', { name: 'Export PNG' });
        await expect(exportButton).toBeVisible();

        await exportButton.click();

        await expect(page.locator('body')).toHaveAttribute('data-roster-export-last-status', 'success');
    });
});
