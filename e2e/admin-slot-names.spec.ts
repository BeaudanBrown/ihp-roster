import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAs, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const e2eRosterPath = '/ShowRosterWeek?weekOffset=0&rosterGroupId=a1000000-0000-0000-0000-000000000211';

test.describe('Roster week columns', () => {
    test('manager can add and delete a draft-week spacing column with live refresh', async ({ browser }) => {
        const editorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const editorPage = await editorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAs(editorPage, 'e2e-test@example.com', 'test-password-123');
        await loginAs(viewerPage, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(editorPage, e2eRosterPath, '.roster-grid');
        await gotoWhenReady(viewerPage, e2eRosterPath, '.roster-grid');
        await expect(editorPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        const editorGrid = editorPage.locator('.roster-grid');
        const viewerGrid = viewerPage.locator('.roster-grid');
        const initialEditorStaffSelects = await editorGrid.locator('select[name="staffId"]').count();
        const initialViewerStaffSelects = await viewerGrid.locator('select[name="staffId"]').count();
        const initialEditorColumnHeaders = await editorGrid.locator('.roster-block-header').count();
        const initialViewerColumnHeaders = await viewerGrid.locator('.roster-block-header').count();

        await expect(editorPage.locator('.roster-slot-column-name-input')).toHaveCount(0);
        await expect(editorPage.getByRole('button', { name: 'Add roster column' })).not.toBeVisible();
        await editorPage.getByRole('button', { name: 'Roster actions' }).click();
        await editorPage.getByLabel('Edit roster columns').check();
        await expect(editorPage.getByRole('button', { name: 'Finish editing roster columns' })).toBeVisible();

        const createResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/CreateRosterWeekSlotDefinition');
        });
        await editorPage.getByRole('button', { name: 'Add roster column' }).click();
        const createResponse = await createResponsePromise;
        expect(createResponse.status(), await createResponse.text()).toBe(200);

        await expect(editorPage.locator('.roster-slot-column-name-input')).toHaveCount(0);
        await expect.poll(() => editorGrid.locator('.roster-block-header').count()).toBeGreaterThan(initialEditorColumnHeaders);
        await expect.poll(() => viewerGrid.locator('.roster-block-header').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBeGreaterThan(initialViewerColumnHeaders);
        await expect.poll(() => editorGrid.locator('select[name="staffId"]').count()).toBeGreaterThan(initialEditorStaffSelects);
        await expect.poll(() => viewerGrid.locator('select[name="staffId"]').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBeGreaterThan(initialViewerStaffSelects);

        const deleteResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'DELETE' && response.url().includes('/DeleteRosterWeekSlotDefinition');
        });
        await editorPage
            .locator('.roster-block-header')
            .last()
            .getByRole('button', { name: 'Remove roster column' })
            .click();
        const deleteResponse = await deleteResponsePromise;
        expect(deleteResponse.status(), await deleteResponse.text()).toBe(200);

        await expect.poll(() => editorGrid.locator('.roster-block-header').count()).toBe(initialEditorColumnHeaders);
        await expect.poll(() => viewerGrid.locator('.roster-block-header').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(initialViewerColumnHeaders);
        await editorPage.getByRole('button', { name: 'Finish editing roster columns' }).click();
        await expect(editorPage.getByRole('button', { name: 'Add roster column' })).not.toBeVisible();

        await editorContext.close();
        await viewerContext.close();
    });
});
