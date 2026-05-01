import { test, expect } from '@playwright/test';
import {
    addRowToRosterDay,
    editableRosterRows,
    firstEditableRosterDaySection,
    openRoster,
    removeRowFromRosterDay,
    rosterDayAddButtonForSection,
    rosterDayRemoveButtonForSection,
} from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page);
}

test.describe('Roster row controls', () => {
    test('adds and removes the last row from the day header controls', async ({ page }) => {
        await loginAndOpenRoster(page);

        const daySectionId = await firstEditableRosterDaySection(page).getAttribute('id');
        expect(daySectionId).toBeTruthy();

        const daySection = page.locator(`#${daySectionId}`);
        const dayRows = editableRosterRows(daySection);
        let baselineRowCount = await dayRows.count();

        if (baselineRowCount < 2) {
            await addRowToRosterDay(daySection);
            await expect(dayRows).toHaveCount(baselineRowCount + 1);
            baselineRowCount += 1;
        }

        await expect(await rosterDayAddButtonForSection(daySection)).toBeVisible();
        await addRowToRosterDay(daySection);
        await expect(dayRows).toHaveCount(baselineRowCount + 1);

        await expect(await rosterDayRemoveButtonForSection(daySection)).toBeEnabled();
        await removeRowFromRosterDay(daySection);
        await expect(dayRows).toHaveCount(baselineRowCount);
    });

    test('keeps the staff panel sticky, viewport-capped, and internally scrollable', async ({ page }) => {
        await loginAndOpenRoster(page);
        await page.setViewportSize({ width: 1440, height: 900 });

        const sidebarMetrics = await page.evaluate(() => {
            const side = document.querySelector('.roster-layout-side');
            const panel = document.querySelector('.roster-staff-panel');
            const list = document.querySelector('.roster-staff-panel-list');

            if (!(side instanceof HTMLElement) || !(panel instanceof HTMLElement) || !(list instanceof HTMLElement)) {
                return null;
            }

            const sideStyle = getComputedStyle(side);
            const panelStyle = getComputedStyle(panel);
            const listStyle = getComputedStyle(list);

            return {
                sidePosition: sideStyle.position,
                sideTop: sideStyle.top,
                panelHeight: Math.round(panel.getBoundingClientRect().height),
                viewportHeight: window.innerHeight,
                panelOverflow: panelStyle.overflowY,
                listOverflow: listStyle.overflowY,
                listScrollable: list.scrollHeight > list.clientHeight,
            };
        });

        expect(sidebarMetrics).not.toBeNull();
        expect(sidebarMetrics?.sidePosition).toBe('sticky');
        expect(sidebarMetrics?.sideTop).not.toBe('auto');
        expect(sidebarMetrics?.panelHeight ?? 0).toBeLessThanOrEqual(sidebarMetrics?.viewportHeight ?? 0);
        expect(sidebarMetrics?.panelOverflow).toBe('hidden');
        expect(sidebarMetrics?.listOverflow).toBe('auto');
    });
});
