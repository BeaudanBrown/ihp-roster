import { test, expect } from '@playwright/test';
import {
    rosterColumnEditDoneDomAttr,
    rosterColumnEditingDomAttr,
    rosterColumnEditingStates,
    rosterColumnEditorDomAttr,
    rosterColumnEditStartDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { openRoster } from './support/roster';
import { webauthnBaseURL } from './support/passkeys';

test.use({ baseURL: webauthnBaseURL });

test.describe('Roster week columns', () => {
    test('manager can add and delete a draft-week spacing column with live refresh', async ({ browser }) => {
        const editorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const editorPage = await editorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await openRoster(editorPage);
        await openRoster(viewerPage);
        await expect(editorPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });

        const editorFrame = editorPage.locator(`[${rosterColumnEditorDomAttr}="true"]`);
        const editorGrid = editorPage.locator('.roster-grid');
        const viewerGrid = viewerPage.locator('.roster-grid');
        const editStart = editorFrame.locator(`[${rosterColumnEditStartDomAttr}="true"]`);
        const editDone = editorFrame.locator(`[${rosterColumnEditDoneDomAttr}="true"]`);
        const initialEditorLaunchers = await editorGrid.locator('[data-roster-shift-launcher="true"]').count();
        const initialViewerLaunchers = await viewerGrid.locator('[data-roster-shift-launcher="true"]').count();
        const initialEditorColumnHeaders = await editorGrid.locator('.roster-block-header').count();
        const initialViewerColumnHeaders = await viewerGrid.locator('.roster-block-header').count();

        await expect(editorPage.locator('.roster-slot-column-name-input')).toHaveCount(0);
        await expect(editorPage.getByRole('button', { name: 'Add roster column' })).not.toBeVisible();
        await expect(editorGrid.locator('.roster-grid-header-row-subheads')).toBeVisible();
        await expect(editorGrid.locator('.roster-grid-header-row-blocks')).toBeHidden();
        await expect(editorFrame).toHaveAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.inactive);
        await expect(editStart).toHaveAttribute('aria-label', 'Edit roster columns');
        await editStart.click();
        await expect(editorFrame).toHaveAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.active);
        await expect(editStart).toHaveAttribute('aria-pressed', 'true');
        await expect(editDone).toBeVisible();
        await expect(editDone).toHaveAttribute('aria-label', 'Finish editing roster columns');
        await expect(editorGrid.locator('.roster-grid-header-row-subheads')).toBeHidden();
        await expect(editorGrid.locator('.roster-grid-header-row-blocks')).toBeVisible();

        const createResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/CreateRosterWeekSlotDefinition');
        });
        await editorPage.getByRole('button', { name: 'Add roster column' }).click();
        const createResponse = await createResponsePromise;
        expect(createResponse.status()).toBe(200);

        await expect(editorPage.locator('.roster-slot-column-name-input')).toHaveCount(0);
        await expect.poll(() => editorGrid.locator('.roster-block-header').count()).toBeGreaterThan(initialEditorColumnHeaders);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect.poll(() => viewerGrid.locator('.roster-block-header').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBeGreaterThan(initialViewerColumnHeaders);
        await expect.poll(() => editorGrid.locator('[data-roster-shift-launcher="true"]').count()).toBeGreaterThan(initialEditorLaunchers);
        await expect.poll(() => viewerGrid.locator('[data-roster-shift-launcher="true"]').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBeGreaterThan(initialViewerLaunchers);
        await expect(editorFrame).toHaveAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.active);
        await expect(editDone).toBeVisible();

        const deleteResponsePromise = editorPage.waitForResponse((response) => {
            return response.request().method() === 'POST' && response.url().includes('/RemoveRosterWeekSlotDefinition');
        });
        await editorPage
            .locator('.roster-block-header')
            .last()
            .getByRole('button', { name: 'Remove roster column' })
            .click();
        const deleteResponse = await deleteResponsePromise;
        expect(deleteResponse.status()).toBe(200);

        await expect.poll(() => editorGrid.locator('.roster-block-header').count()).toBe(initialEditorColumnHeaders);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect.poll(() => viewerGrid.locator('.roster-block-header').count(), { timeout: E2E_TIMEOUT.liveUpdate }).toBe(initialViewerColumnHeaders);
        await expect(editorFrame).toHaveAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.active);
        await editDone.click();
        await expect(editorFrame).toHaveAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.inactive);
        await expect(editStart).toHaveAttribute('aria-pressed', 'false');
        await expect(editorPage.getByRole('button', { name: 'Add roster column' })).not.toBeVisible();

        await editorContext.close();
        await viewerContext.close();
    });
});
