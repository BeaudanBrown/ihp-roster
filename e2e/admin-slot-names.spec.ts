import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAs, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

function columnInput(page: import('@playwright/test').Page, name: string) {
    return page.locator(`input.roster-slot-column-name-input[value="${name}"]`);
}

test.describe('Roster week columns', () => {
    test('manager can add rename and delete a draft-week roster column with live refresh', async ({ browser }) => {
        const editorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const editorPage = await editorContext.newPage();
        const viewerPage = await viewerContext.newPage();
        const columnName = `Graveyard ${Date.now()}`;
        const renamedColumnName = `${columnName} Updated`;

        await loginAs(editorPage, 'e2e-test@example.com', 'test-password-123');
        await loginAs(viewerPage, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(editorPage, e2eRosterPath, 'table.roster-grid');
        await gotoWhenReady(viewerPage, e2eRosterPath, 'table.roster-grid');
        await expect(editorPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        const editorGrid = editorPage.locator('table.roster-grid');
        const viewerGrid = viewerPage.locator('table.roster-grid');
        const initialEditorStaffSelects = await editorGrid.locator('select[name="staffId"]').count();
        const initialViewerStaffSelects = await viewerGrid.locator('select[name="staffId"]').count();

        const createResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/CreateRosterWeekSlotDefinition');
        });
        await editorPage.locator('input[placeholder="Column name"]').fill(columnName);
        await editorPage.getByRole('button', { name: 'Add roster column' }).click();
        const createResponse = await createResponsePromise;
        expect(createResponse.status(), await createResponse.text()).toBe(200);

        await expect(columnInput(editorPage, columnName)).toBeVisible();
        await expect(columnInput(viewerPage, columnName)).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect.poll(() => editorGrid.locator('select[name="staffId"]').count()).toBeGreaterThan(initialEditorStaffSelects);
        await expect.poll(() => viewerGrid.locator('select[name="staffId"]').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBeGreaterThan(initialViewerStaffSelects);

        const renameResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/UpdateRosterWeekSlotDefinition');
        });
        await columnInput(editorPage, columnName).fill(renamedColumnName);
        await editorPage.keyboard.press('Tab');
        const renameResponse = await renameResponsePromise;
        expect(renameResponse.status(), await renameResponse.text()).toBe(200);
        await expect(columnInput(editorPage, renamedColumnName)).toBeVisible();
        await expect(columnInput(viewerPage, renamedColumnName)).toBeVisible({ timeout: E2E_TIMEOUT.liveUpdate });
        await expect(columnInput(viewerPage, columnName)).toHaveCount(0);

        editorPage.once('dialog', (dialog) => dialog.accept());
        const deleteResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'DELETE' && response.url().includes('/DeleteRosterWeekSlotDefinition');
        });
        await editorPage
            .locator('th.roster-block-header')
            .filter({ has: columnInput(editorPage, renamedColumnName) })
            .getByRole('button', { name: 'Remove roster column' })
            .click();
        const deleteResponse = await deleteResponsePromise;
        expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);

        await expect(columnInput(editorPage, renamedColumnName)).toHaveCount(0);
        await expect(columnInput(viewerPage, renamedColumnName)).toHaveCount(0, { timeout: E2E_TIMEOUT.liveUpdate });

        await editorContext.close();
        await viewerContext.close();
    });
});
