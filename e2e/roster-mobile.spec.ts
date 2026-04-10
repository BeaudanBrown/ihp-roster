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

    test('keeps editable roster cells reachable without requiring the staff sidebar first', async ({ page }) => {
        const firstTimeField = page.locator('[data-time-picker-field]').first();
        const firstStaffSelect = page.locator('.slot-staff-input').first();
        const firstNoteField = page.locator('.slot-note-input').first();

        await expect(firstTimeField).toBeVisible();
        await expect(firstStaffSelect).toBeVisible();
        await expect(firstNoteField).toBeVisible();

        await firstTimeField.scrollIntoViewIfNeeded();
        await firstStaffSelect.scrollIntoViewIfNeeded();
        await firstNoteField.scrollIntoViewIfNeeded();

        const reachable = await page.evaluate(() => {
            const timeField = document.querySelector('[data-time-picker-field]');
            const staffField = document.querySelector('.slot-staff-input');
            const noteField = document.querySelector('.slot-note-input');

            if (!(timeField instanceof HTMLElement) || !(staffField instanceof HTMLElement) || !(noteField instanceof HTMLElement)) {
                return null;
            }

            const viewportWidth = window.innerWidth;
            const elements = [timeField, staffField, noteField].map((element) => {
                const rect = element.getBoundingClientRect();
                return {
                    left: Math.round(rect.left),
                    right: Math.round(rect.right),
                };
            });

            return {
                viewportWidth,
                elements,
            };
        });

        expect(reachable).not.toBeNull();
        for (const element of reachable?.elements ?? []) {
            expect(element.left).toBeGreaterThanOrEqual(0);
            expect(element.right).toBeLessThanOrEqual((reachable?.viewportWidth ?? 0) + 1);
        }
    });
});
