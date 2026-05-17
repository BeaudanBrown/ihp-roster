import { test, expect } from '@playwright/test';
import {
    editableRosterRows,
    expectContainerToManageHorizontalOverflow,
    expectNoHorizontalViewportOverflow,
    firstRosterDayAddButton,
    firstRosterDayRemoveButton,
    openRoster,
} from './test-helpers';

test.describe('Roster mobile baseline', () => {
    test.beforeEach(async ({ page }) => {
        await openRoster(page);
        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expect(page.locator('#roster-content')).toBeVisible();
        await expect(page.locator('.roster-grid')).toBeVisible();
    });

    test('keeps the roster shell within the viewport and contains any grid overflow locally', async ({ page }) => {
        await expectNoHorizontalViewportOverflow(page);
        await expectContainerToManageHorizontalOverflow(page, '.roster-slots-scroller');

        const rosterTableMetrics = await page.locator('.roster-grid-frame').first().evaluate((frame) => {
            if (!(frame instanceof HTMLElement)) {
                throw new Error('Expected roster grid frame to be an HTMLElement');
            }

            const scroller = frame.querySelector('.roster-slots-scroller');
            const grid = frame.querySelector('.roster-grid');
            const dayRail = frame.querySelector('.roster-day-rail');
            const daySection = frame.querySelector('.roster-day-rail-section');
            const firstGridSection = frame.querySelector('.roster-grid-day-section');

            if (
                !(scroller instanceof HTMLElement)
                || !(grid instanceof HTMLElement)
                || !(dayRail instanceof HTMLElement)
                || !(daySection instanceof HTMLElement)
                || !(firstGridSection instanceof HTMLElement)
            ) {
                return null;
            }

            const railBefore = dayRail.getBoundingClientRect();
            const scrollerBefore = scroller.getBoundingClientRect();
            scroller.scrollLeft = Math.floor((scroller.scrollWidth - scroller.clientWidth) / 2);
            const railAfter = dayRail.getBoundingClientRect();
            const scrollerAfter = scroller.getBoundingClientRect();

            return {
                scrollerClientWidth: scroller.clientWidth,
                scrollerScrollWidth: scroller.scrollWidth,
                overflowX: getComputedStyle(scroller).overflowX,
                gridMinWidth: getComputedStyle(grid).minWidth,
                dayRailPosition: getComputedStyle(dayRail).position,
                daySectionPosition: getComputedStyle(daySection).position,
                firstDayRailHeight: Math.round(daySection.getBoundingClientRect().height),
                firstGridSectionHeight: Math.round(firstGridSection.getBoundingClientRect().height),
                railLeftBefore: Math.round(railBefore.left),
                railLeftAfter: Math.round(railAfter.left),
                railRightAfter: Math.round(railAfter.right),
                scrollerLeftBefore: Math.round(scrollerBefore.left),
                scrollerLeftAfter: Math.round(scrollerAfter.left),
                cellWidths: Array.from(grid.querySelectorAll('.day-row:first-child > [role="gridcell"]')).map((cell) =>
                    Math.round(cell.getBoundingClientRect().width)
                ),
            };
        });

        expect(rosterTableMetrics).not.toBeNull();
        expect(rosterTableMetrics?.overflowX).toBe('auto');
        expect(rosterTableMetrics?.scrollerScrollWidth).toBeGreaterThan(rosterTableMetrics?.scrollerClientWidth ?? 0);
        expect(rosterTableMetrics?.gridMinWidth).not.toBe('0px');
        expect(rosterTableMetrics?.dayRailPosition).toBe('static');
        expect(rosterTableMetrics?.daySectionPosition).toBe('static');
        expect(rosterTableMetrics?.firstDayRailHeight).toBe(rosterTableMetrics?.firstGridSectionHeight);
        expect(rosterTableMetrics?.railLeftAfter).toBe(rosterTableMetrics?.railLeftBefore);
        expect(rosterTableMetrics?.scrollerLeftAfter).toBe(rosterTableMetrics?.scrollerLeftBefore);
        expect(rosterTableMetrics?.scrollerLeftAfter).toBeGreaterThanOrEqual((rosterTableMetrics?.railRightAfter ?? 0) - 1);
        expect(rosterTableMetrics?.cellWidths.length).toBeGreaterThanOrEqual(3);
        expect(rosterTableMetrics?.cellWidths[1]).toBeGreaterThan(rosterTableMetrics?.cellWidths[0] ?? 0);

        const metrics = await page.evaluate(() => {
            const side = document.querySelector('.roster-layout-side');
            const panel = document.querySelector('.roster-staff-panel');
            const list = document.querySelector('.roster-staff-panel-list');

            if (!(side instanceof HTMLElement) || !(panel instanceof HTMLElement) || !(list instanceof HTMLElement)) {
                return null;
            }

            return {
                sidePosition: getComputedStyle(side).position,
                panelOverflowY: getComputedStyle(panel).overflowY,
                listOverflowY: getComputedStyle(list).overflowY,
            };
        });

        expect(metrics).not.toBeNull();
        expect(metrics?.sidePosition).toBe('static');
        expect(metrics?.panelOverflowY).not.toBe('hidden');
        expect(metrics?.listOverflowY).not.toBe('auto');
    });

    test('preserves core week navigation and row controls on a narrow viewport', async ({ page }) => {
        await expect(firstRosterDayAddButton(page)).toBeVisible();
        await expect(firstRosterDayRemoveButton(page)).toBeVisible();

        const shell = page.locator('#roster-week-shell');
        const initialShellHtml = await shell.evaluate((el) => el.outerHTML);

        const nextWeekButton = page.getByRole('link', { name: 'Next week' });
        await nextWeekButton.click();
        await expect(shell).toBeVisible();
        const nextShellHtml = await shell.evaluate((el) => el.outerHTML);
        expect(nextShellHtml).not.toBe(initialShellHtml);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('uses compact closed-day controls without add or remove actions', async ({ page }) => {
        const firstDayRailSection = page.locator('.roster-day-rail-section').first();
        const firstSlotDaySection = page.locator('[data-roster-day-section="true"]').first();
        const closeButton = firstDayRailSection.locator('[data-roster-day-closed-toggle="true"]');

        await expect(closeButton).toBeVisible();
        await expect(closeButton.locator('.bi-unlock')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-remove="true"]')).toBeVisible();

        await closeButton.click();

        const reopenButton = firstDayRailSection.locator('[data-roster-day-closed-toggle="true"]');
        await expect(reopenButton).toContainText('CLOSED');
        await expect(reopenButton.locator('.bi-lock-fill')).toBeVisible();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toHaveCount(0);
        await expect(firstDayRailSection.locator('[data-roster-day-remove="true"]')).toHaveCount(0);
        await expect(firstSlotDaySection.locator('[data-roster-row]')).toHaveCount(2);

        await reopenButton.click();
        await expect(firstDayRailSection.locator('[data-roster-day-add="true"]')).toBeVisible();
    });

    test('keeps editable roster cells reachable without requiring the staff sidebar first', async ({ page }) => {
        const firstTimeField = page.locator('[data-time-picker-field]').first();
        const firstStaffSelect = page.locator('.slot-staff-input').first();
        const firstShiftTypeSelect = page.locator('.slot-shift-type-input').first();

        await expect(firstTimeField).toBeVisible();
        await expect(firstStaffSelect).toBeVisible();
        await expect(firstShiftTypeSelect).toBeVisible();

        for (const field of [firstTimeField, firstStaffSelect, firstShiftTypeSelect]) {
            await field.scrollIntoViewIfNeeded();

            const reachable = await field.evaluate((element) => {
                if (!(element instanceof HTMLElement)) {
                    throw new Error('Expected roster field to be an HTMLElement');
                }

                const scroller = element.closest('.roster-slots-scroller');
                if (!(scroller instanceof HTMLElement)) {
                    throw new Error('Expected roster field to live in the slot scroller');
                }

                element.scrollIntoView({ block: 'nearest', inline: 'center' });
                const rect = element.getBoundingClientRect();
                const scrollerRect = scroller.getBoundingClientRect();
                const visibleLeft = Math.max(rect.left, scrollerRect.left, 0);
                const visibleRight = Math.min(rect.right, scrollerRect.right, window.innerWidth);

                return {
                    visibleWidth: Math.round(Math.max(0, visibleRight - visibleLeft)),
                };
            });

            expect(reachable.visibleWidth).toBeGreaterThan(20);
            await expectNoHorizontalViewportOverflow(page);
        }
    });
});
