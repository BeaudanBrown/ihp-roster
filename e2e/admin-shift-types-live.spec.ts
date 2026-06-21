import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';
import { E2E_TIMEOUT, openAdminWithSeededPasskeySession } from './test-helpers';

async function duplicateIds(page: Page) {
    return page.evaluate(() => {
        const counts = new Map<string, number>();
        document.querySelectorAll<HTMLElement>('[id]').forEach((element) => {
            counts.set(element.id, (counts.get(element.id) ?? 0) + 1);
        });
        return Array.from(counts.entries())
            .filter(([, count]) => count > 1)
            .map(([id, count]) => ({ id, count }))
            .sort((left, right) => left.id.localeCompare(right.id));
    });
}

test.describe('Admin shift types live updates', () => {
    test('changing the create-row pay-rate select does not swap the admin page into the shift-types fragment', async ({ page }) => {
        await openAdminWithSeededPasskeySession(page);
        await page.getByRole('button', { name: 'Shift Types' }).click();
        await expect(page.locator('#shift-types-collapse')).toHaveClass(/show/, { timeout: E2E_TIMEOUT.action });

        const createPayRateSelect = page.locator('#new-shift-type-pay-rate');
        await expect(createPayRateSelect).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await createPayRateSelect.selectOption({ index: 1 });
        await page.waitForTimeout(E2E_TIMEOUT.quick);

        await expect(page.locator('#admin-shift-types-fragment #admin-config-sections')).toHaveCount(0);
        await expect(page.locator('#admin-shift-types-fragment #shift-types')).toHaveCount(0);
        await expect(page.locator('#admin-shift-types-fragment #app')).toHaveCount(0);
        expect(await duplicateIds(page)).toEqual([]);
    });

    test('replace only the shift types fragment during passive live refreshes', async ({ browser }) => {
        const viewerContext = await browser.newContext();
        const actorContext = await browser.newContext();
        const viewer = await viewerContext.newPage();
        const actor = await actorContext.newPage();

        try {
            await openAdminWithSeededPasskeySession(viewer);
            await viewer.getByRole('button', { name: 'Shift Types' }).click();
            await expect(viewer.locator('#shift-types-collapse')).toHaveClass(/show/, { timeout: E2E_TIMEOUT.action });
            await expect(viewer.locator('#admin-shift-types-fragment')).toHaveAttribute('data-live-update-client-id', /.+/, { timeout: E2E_TIMEOUT.liveUpdate });
            expect(await duplicateIds(viewer)).toEqual([]);

            await openAdminWithSeededPasskeySession(actor);
            await actor.getByRole('button', { name: 'Shift Types' }).click();
            await expect(actor.locator('#shift-types-collapse')).toHaveClass(/show/, { timeout: E2E_TIMEOUT.action });
            await expect(actor.locator('#admin-shift-types-fragment')).toHaveAttribute('data-live-update-client-id', /.+/, { timeout: E2E_TIMEOUT.liveUpdate });
            expect(await duplicateIds(actor)).toEqual([]);

            const shiftTypeName = `Live Shift Type ${Date.now()}`;
            await actor.locator('#new-shift-type-name').fill(shiftTypeName);
            await actor.locator('#admin-shift-types-fragment form').first().getByRole('button', { name: 'Add' }).click();

            await expect(actor.locator(`#admin-shift-types-fragment input[value="${shiftTypeName}"]`)).toHaveCount(1, { timeout: E2E_TIMEOUT.assertion });
            await expect(viewer.locator(`#admin-shift-types-fragment input[value="${shiftTypeName}"]`)).toHaveCount(1, { timeout: E2E_TIMEOUT.liveUpdate });

            await expect(viewer.locator('#admin-shift-types-fragment #admin-config-sections')).toHaveCount(0);
            await expect(viewer.locator('#admin-shift-types-fragment #shift-types')).toHaveCount(0);
            expect(await duplicateIds(viewer)).toEqual([]);
        } finally {
            await actorContext.close();
            await viewerContext.close();
        }
    });
});
