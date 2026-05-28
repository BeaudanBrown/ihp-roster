import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAs, openRoster } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster week overview', () => {
    test('renders a static week label without the month overview trigger', async ({ page }) => {
        await openRoster(page);

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator('[data-week-overview-fragment-mount="true"]')).toHaveCount(0);
        await expect(page.locator('.roster-week-nav-label')).toContainText('Week of');
    });

    test('exports the live roster as a jpg from the roster actions menu', async ({ page }) => {
        await openRoster(page);

        await page.getByRole('button', { name: 'Roster settings' }).click();
        const exportButton = page.getByRole('button', { name: 'Export JPG' });
        await expect(exportButton).toBeVisible();

        await exportButton.click();

        await expect(page.locator('body')).toHaveAttribute('data-roster-export-last-status', 'success');
    });

    test('keeps the desktop roster grid fitted without page-level horizontal scrolling', async ({ page }) => {
        await openRoster(page);

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

        await expect(page.getByRole('button', { name: 'Open roster week overview' })).toHaveCount(0);
        await expect(page.locator('[data-week-overview-fragment-mount="true"]')).toHaveCount(0);
    });
});
