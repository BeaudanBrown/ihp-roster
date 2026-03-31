import { test, expect } from '@playwright/test';

async function loginAndOpenRoster(page) {
    await page.goto('/NewSession');
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);

    const createDraftButton = page.locator('button:has-text("Create Draft Roster")');
    if (await createDraftButton.isVisible()) {
        await createDraftButton.click();
    }

    await expect(page.locator('#roster-content')).toBeVisible();
    await expect(page.locator('table.roster-grid')).toBeVisible();
}

test.describe('Roster row controls', () => {
    test('adds and removes the last row from the day header controls', async ({ page }) => {
        await loginAndOpenRoster(page);

        const firstDaySection = page.locator('tbody[data-roster-day-section]').first();
        const dayRows = firstDaySection.locator('tr[data-roster-row]');
        const initialRowCount = await dayRows.count();

        const addButton = page.locator('[data-roster-day-add="true"]').first();
        await addButton.click();
        await expect(dayRows).toHaveCount(initialRowCount + 1);

        const removeButton = page.locator('[data-roster-day-remove="true"]').first();
        await removeButton.click();
        await expect(dayRows).toHaveCount(initialRowCount);
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
