import { test, expect } from '@playwright/test';
import {
    editableRosterRows,
    expectContainerToManageHorizontalOverflow,
    expectNoHorizontalViewportOverflow,
    firstRosterDayAddButton,
    firstRosterDayRemoveButton,
    gotoWhenReady,
    loginAs,
} from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster mobile baseline', () => {
    test.beforeEach(async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, e2eRosterPath, 'table.roster-grid');
        await expect(page.locator('#roster-week-shell')).toBeVisible();
        await expect(page.locator('#roster-content')).toBeVisible();
        await expect(page.locator('table.roster-grid')).toBeVisible();
    });

    test('keeps the roster shell within the viewport and contains any table overflow locally', async ({ page }) => {
        await expectNoHorizontalViewportOverflow(page);
        await expectContainerToManageHorizontalOverflow(page, '.table-responsive');

        const rosterTableMetrics = await page.locator('.roster-layout .table-responsive').first().evaluate((container) => {
            if (!(container instanceof HTMLElement)) {
                throw new Error('Expected roster table container to be an HTMLElement');
            }

            const table = container.querySelector('table.roster-grid');
            const dayHeader = container.querySelector('.roster-day-column');
            const dayCell = container.querySelector('.day-label');

            if (!(table instanceof HTMLElement) || !(dayHeader instanceof HTMLElement) || !(dayCell instanceof HTMLElement)) {
                return null;
            }

            return {
                containerClientWidth: container.clientWidth,
                containerScrollWidth: container.scrollWidth,
                overflowX: getComputedStyle(container).overflowX,
                tableMinWidth: getComputedStyle(table).minWidth,
                dayHeaderPosition: getComputedStyle(dayHeader).position,
                dayCellPosition: getComputedStyle(dayCell).position,
                columnWidths: Array.from(table.querySelectorAll('col')).map((col) =>
                    Math.round(Number.parseFloat(getComputedStyle(col).width))
                ),
            };
        });

        expect(rosterTableMetrics).not.toBeNull();
        expect(rosterTableMetrics?.overflowX).toBe('auto');
        expect(rosterTableMetrics?.containerScrollWidth).toBeGreaterThan(rosterTableMetrics?.containerClientWidth ?? 0);
        expect(rosterTableMetrics?.tableMinWidth).not.toBe('0px');
        expect(rosterTableMetrics?.dayHeaderPosition).toBe('sticky');
        expect(rosterTableMetrics?.dayCellPosition).toBe('sticky');
        expect(rosterTableMetrics?.columnWidths[1]).toBeGreaterThan(rosterTableMetrics?.columnWidths[3] ?? 0);
        expect(rosterTableMetrics?.columnWidths[2]).toBeGreaterThan(rosterTableMetrics?.columnWidths[1] ?? 0);

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
        const firstDaySection = page.locator('tbody[data-roster-day-section="true"]').first();
        const closeButton = firstDaySection.locator('[data-roster-day-closed-toggle="true"]');

        await expect(closeButton).toBeVisible();
        await expect(closeButton.locator('.bi-unlock')).toBeVisible();
        await expect(firstDaySection.locator('[data-roster-day-add="true"]')).toBeVisible();
        await expect(firstDaySection.locator('[data-roster-day-remove="true"]')).toBeVisible();

        await closeButton.click();

        const reopenButton = firstDaySection.locator('[data-roster-day-closed-toggle="true"]');
        await expect(reopenButton).toContainText('CLOSED');
        await expect(reopenButton.locator('.bi-lock-fill')).toBeVisible();
        await expect(firstDaySection.locator('[data-roster-day-add="true"]')).toHaveCount(0);
        await expect(firstDaySection.locator('[data-roster-day-remove="true"]')).toHaveCount(0);
        await expect(firstDaySection.locator('tr[data-roster-row]')).toHaveCount(2);

        await reopenButton.click();
        await expect(firstDaySection.locator('[data-roster-day-add="true"]')).toBeVisible();
    });

    test('keeps editable roster cells reachable without requiring the staff sidebar first', async ({ page }) => {
        const firstTimeField = page.locator('[data-time-picker-field]').first();
        const firstStaffSelect = page.locator('.slot-staff-input').first();
        const firstNoteField = page.locator('.slot-note-input').first();

        await expect(firstTimeField).toBeVisible();
        await expect(firstStaffSelect).toBeVisible();
        await expect(firstNoteField).toBeVisible();

        for (const field of [firstTimeField, firstStaffSelect, firstNoteField]) {
            await field.scrollIntoViewIfNeeded();

            const reachable = await field.evaluate((element) => {
                if (!(element instanceof HTMLElement)) {
                    throw new Error('Expected roster field to be an HTMLElement');
                }

                const rect = element.getBoundingClientRect();
                return {
                    left: Math.round(rect.left),
                    right: Math.round(rect.right),
                    viewportWidth: window.innerWidth,
                };
            });

            expect(reachable.left).toBeGreaterThanOrEqual(-10);
            expect(reachable.right).toBeLessThanOrEqual(reachable.viewportWidth + 10);
            await expectNoHorizontalViewportOverflow(page);
        }
    });
});
