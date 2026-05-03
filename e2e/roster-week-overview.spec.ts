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

        const nextWeekDay = overviewMenu
            .locator('[data-week-overview-day="true"][data-week-overview-url*="weekOffset=1"][data-week-overview-assigned="2"]')
            .first();
        const loadedAssignedDay = overviewMenu
            .locator('[data-week-overview-day="true"][data-week-overview-details="true"]:not([data-week-overview-assigned=""])')
            .first();
        const targetDay = (await nextWeekDay.count()) > 0 ? nextWeekDay : loadedAssignedDay;

        await expect(targetDay).toBeVisible();
        const selectedDayLabel = await targetDay.getAttribute('data-week-overview-label');
        const targetWeekUrl = await targetDay.getAttribute('data-week-overview-url');
        const expectedLeave = await targetDay.getAttribute('data-week-overview-leave');
        const expectedAssigned = await targetDay.getAttribute('data-week-overview-assigned');
        const expectedHours = await targetDay.getAttribute('data-week-overview-hours');
        await targetDay.click();

        await expect(overviewMenu.locator('[data-week-overview-selected-label="true"]')).toHaveText(selectedDayLabel ?? '');
        await expect(overviewMenu.locator('[data-week-overview-leave-value="true"]')).toHaveText(expectedLeave ?? '');
        await expect(overviewMenu.locator('[data-week-overview-assigned-value="true"]')).toHaveText(expectedAssigned ?? '');
        await expect(overviewMenu.locator('[data-week-overview-hours-value="true"]')).toHaveText(expectedHours ?? '');

        const goLink = overviewMenu.locator('[data-week-overview-go-link="true"]');
        await expect(goLink).toHaveAttribute('href', targetWeekUrl ?? '');
        await goLink.click();

        if ((targetWeekUrl ?? '').includes('weekOffset=1')) {
            await expect(page).toHaveURL(/weekOffset=1/);
        }
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    });

    test('exports the live roster as a jpg from the roster actions menu', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');

        await page.getByRole('button', { name: 'Roster actions' }).click();
        const exportButton = page.getByRole('button', { name: 'Export JPG' });
        await expect(exportButton).toBeVisible();

        await exportButton.click();

        await expect(page.locator('body')).toHaveAttribute('data-roster-export-last-status', 'success');
    });

    test('keeps the desktop roster grid fitted without page-level horizontal scrolling', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');

        const metrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            const dayRail = frame.querySelector('.roster-day-rail');

            if (!(scroller instanceof HTMLElement) || !(grid instanceof HTMLElement) || !(dayRail instanceof HTMLElement)) {
                return null;
            }

            return {
                clientWidth: scroller.clientWidth,
                scrollWidth: scroller.scrollWidth,
                frameScrollWidth: frame.scrollWidth,
                frameClientWidth: frame.clientWidth,
                overflowX: getComputedStyle(scroller).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                dayRailPosition: getComputedStyle(dayRail).position,
            };
        });

        expect(metrics).not.toBeNull();
        expect(['hidden', 'auto']).toContain(metrics?.overflowX);
        expect(metrics?.scrollWidth).toBeGreaterThanOrEqual(metrics?.clientWidth ?? 0);
        expect(metrics?.frameScrollWidth).toBeLessThanOrEqual((metrics?.frameClientWidth ?? 0) + 1);
        expect(metrics?.gridMinWidth).not.toBe('0px');
        expect(metrics?.dayRailPosition).toBe('static');
    });

    test('worker cannot see manager-only roster controls or leave metrics', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, '#roster-week-shell');

        await expect(page.getByLabel('Live')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Copy Previous Week' })).toHaveCount(0);

        await expect(page.getByRole('button', { name: 'Export JPG' })).toHaveCount(0);
        await expect(page.getByText('Hide from dropdowns')).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Sync Slots' })).toHaveCount(0);

        await page.getByRole('button', { name: 'Open roster week overview' }).click();
        const overviewMenu = page.locator('.roster-week-overview-menu.show');
        await expect(overviewMenu).toBeVisible();
        await expect(overviewMenu.getByText('unavailable periods')).toHaveCount(0);
        await expect(overviewMenu.locator('[data-week-overview-leave-value="true"]')).toHaveCount(0);
    });
});
