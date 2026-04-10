import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAs } from './test-helpers';

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Admin slot names', () => {
    test('deleting a slot name succeeds and updates the slot-name fragment', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Admin', '#admin-config-sections');

        const slotNamesToggle = page.getByRole('button', { name: 'Slot Names' });
        if ((await slotNamesToggle.getAttribute('aria-expanded')) !== 'true') {
            await slotNamesToggle.click();
        }

        const addedSlotName = `Delete Me ${Date.now()}`;
        const slotNameInputs = page.locator('#admin-slot-names-fragment input[aria-label="Slot name"]');
        const deleteButtons = page.locator('#admin-slot-names-fragment button:has-text("Delete")');
        const initialSlotCount = await slotNameInputs.count();

        const createResponsePromise = page.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/CreateSlotName');
        });

        await page.fill('#new-slot-name', addedSlotName);
        await page.getByRole('button', { name: 'Add Slot' }).click();

        const createResponse = await createResponsePromise;
        expect(createResponse.status(), await createResponse.text()).toBe(200);
        await expect(slotNameInputs).toHaveCount(initialSlotCount + 1);

        const deleteResponsePromise = page.waitForResponse((response) => {
            return response.request().method() === 'DELETE' && response.url().includes('/DeleteSlotName');
        });

        await deleteButtons.last().click();

        const deleteResponse = await deleteResponsePromise;
        const deleteResponseText = await deleteResponse.text();
        expect(deleteResponse.status(), deleteResponseText).toBe(200);

        await expect(slotNameInputs).toHaveCount(initialSlotCount);
        await expect(page.locator('#admin-slot-names-fragment')).not.toContainText(addedSlotName);
    });

    test('creating a slot name leaves an existing roster unchanged until the draft week is synced', async ({ browser }) => {
        const adminContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const adminPage = await adminContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const addedSlotName = `Graveyard ${Date.now()}`;

        await loginAs(adminPage, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(adminPage, '/Admin', '#admin-config-sections');
        await loginAs(viewerPage, 'e2e-admin@example.com', 'test-password-123');
        await gotoWhenReady(viewerPage, e2eRosterPath, 'table.roster-grid');
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: 60000 });

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

        const initialStaffSelectCount = await viewerRow.locator('select[name="staffId"]').count();
        const initialNoteCount = await viewerRow.locator('input[name="note"]').count();

        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(initialStaffSelectCount);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(initialNoteCount);

        await addSlot(addedSlotName);
        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(initialStaffSelectCount);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(initialNoteCount);
        await expect(viewerPage.locator('table.roster-grid')).not.toContainText(addedSlotName);

        await viewerPage.reload();
        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(initialStaffSelectCount);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(initialNoteCount);
        await expect(viewerPage.locator('table.roster-grid')).not.toContainText(addedSlotName);

        const syncResponsePromise = viewerPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/SyncRosterWeekSlotStructure');
        });

        const syncSlotsButton = viewerPage.getByRole('button', { name: 'Sync Slots' });
        if (!(await syncSlotsButton.isVisible().catch(() => false))) {
            await viewerPage.getByRole('button', { name: 'Roster actions' }).click();
            await expect(syncSlotsButton).toBeVisible();
        }

        viewerPage.once('dialog', (dialog) => dialog.accept());
        await syncSlotsButton.click();

        const syncResponse = await syncResponsePromise;
        const syncResponseText = await syncResponse.text();
        expect(syncResponse.status(), syncResponseText).toBe(200);

        await expect(viewerRow.locator('select[name="staffId"]')).toHaveCount(initialStaffSelectCount + 1);
        await expect(viewerRow.locator('input[name="note"]')).toHaveCount(initialNoteCount + 1);
        await expect(viewerPage.locator('table.roster-grid')).toContainText(addedSlotName);

        await adminContext.close();
        await viewerContext.close();
    });
});
