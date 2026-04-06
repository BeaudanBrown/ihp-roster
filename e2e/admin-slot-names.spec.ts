import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAs, openRoster } from './test-helpers';

test.describe('Admin slot names', () => {
    test('deleting a slot name succeeds and updates the slot-name fragment', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Admin', '#admin-config-sections');

        const slotNamesToggle = page.getByRole('button', { name: 'Slot Names' });
        if ((await slotNamesToggle.getAttribute('aria-expanded')) !== 'true') {
            await slotNamesToggle.click();
        }

        const slotNameInput = page.locator('#admin-slot-names-fragment input[aria-label="Slot name"]');
        await expect(slotNameInput).toHaveValue('Early');

        const deleteResponsePromise = page.waitForResponse((response) => {
            return response.request().method() === 'DELETE' && response.url().includes('/DeleteSlotName');
        });

        await page.locator('#admin-slot-names-fragment button:has-text("Delete")').click();

        const deleteResponse = await deleteResponsePromise;
        const deleteResponseText = await deleteResponse.text();
        expect(deleteResponse.status(), deleteResponseText).toBe(200);

        await expect(slotNameInput).toHaveCount(0);
        await expect(page.locator('#admin-slot-names-fragment')).toContainText('No slot names yet for this roster group.');
    });

    test('creating a slot name leaves an existing roster unchanged until the draft week is synced', async ({ browser }) => {
        const adminContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const adminPage = await adminContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const addedSlotName = `Graveyard ${Date.now()}`;

        await loginAs(adminPage, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(adminPage, '/Admin', '#admin-config-sections');
        await openRoster(viewerPage);

        const slotNamesToggle = adminPage.getByRole('button', { name: 'Slot Names' });
        if ((await slotNamesToggle.getAttribute('aria-expanded')) !== 'true') {
            await slotNamesToggle.click();
        }

        async function addSlot(name: string) {
            const createResponsePromise = adminPage.waitForResponse((response) => {
                return response.request().method() === 'POST' && response.url().includes('/CreateSlotName');
            });

            await adminPage.fill('#new-slot-name', name);
            await adminPage.getByRole('button', { name: 'Add Slot' }).click();

            const createResponse = await createResponsePromise;
            const createResponseText = await createResponse.text();
            expect(createResponse.status(), createResponseText).toBe(200);
        }

        const viewerRow = viewerPage.locator('tr[data-roster-row]').filter({ has: viewerPage.locator('select[name="staffId"]') }).first();
        if (await adminPage.locator('#admin-slot-names-fragment').getByText('No slot names yet for this roster group.').isVisible().catch(() => false)) {
            await addSlot('Early');
        }

        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(1);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(1);

        await addSlot(addedSlotName);
        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(1);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(1);
        await expect(viewerPage.locator('table.roster-grid')).not.toContainText(addedSlotName);

        await viewerPage.reload();
        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(1);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(1);
        await expect(viewerPage.locator('table.roster-grid')).not.toContainText(addedSlotName);

        const syncResponsePromise = viewerPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/SyncRosterWeekSlotStructure');
        });

        viewerPage.once('dialog', (dialog) => dialog.accept());
        await viewerPage.getByRole('button', { name: 'Sync Slots' }).click();

        const syncResponse = await syncResponsePromise;
        const syncResponseText = await syncResponse.text();
        expect(syncResponse.status(), syncResponseText).toBe(200);

        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(2);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(2);
        await expect(viewerPage.locator('table.roster-grid')).toContainText(addedSlotName);

        await adminContext.close();
        await viewerContext.close();
    });
});
