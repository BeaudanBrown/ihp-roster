import { test, expect, type Page } from '@playwright/test';
import {
    dialogCloseDomAttr,
    dialogOverlayMountDomId,
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortRowDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    addRowToRosterDay,
    fillRosterShiftDialogDefaults,
    firstEditableRosterDaySection,
    openRoster,
    openRosterShiftDialog,
    rosterShiftDialogStaffOptionValues,
    saveRosterShiftDialog,
} from './test-helpers';

const actorDuplicateConflictWeekOffset = 137;
const multiviewDuplicateConflictWeekOffset = 138;

async function loginAndOpenRoster(page: Page, weekOffset = actorDuplicateConflictWeekOffset) {
    await openRoster(page, { weekOffset });
}

function editableRosterRows(page: Page) {
    return page.locator('[data-roster-row]:has([data-roster-shift-launcher="true"])');
}

async function ensureTwoEditableRosterRows(page: Page) {
    const rows = editableRosterRows(page);
    const initialCount = await rows.count();
    if (initialCount >= 2) {
        return;
    }

    await addRowToRosterDay(firstEditableRosterDaySection(page));
    await expect
        .poll(async () => editableRosterRows(page).count(), { timeout: E2E_TIMEOUT.liveUpdate })
        .toBeGreaterThanOrEqual(2);
}

function rowShiftLauncher(page: Page, rowIndex: number) {
    return editableRosterRows(page).nth(rowIndex).locator('[data-roster-shift-launcher="true"]').first();
}

async function staffOptionsForRow(page: Page, rowIndex: number) {
    await openRosterShiftDialog(page, rowShiftLauncher(page, rowIndex));
    const values = await rosterShiftDialogStaffOptionValues(page);
    await page.locator(`[${dialogCloseDomAttr}]`).first().click();
    await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty({ timeout: E2E_TIMEOUT.action });
    return values;
}

async function assignStaffToRow(page: Page, rowIndex: number, staffId: string) {
    await openRosterShiftDialog(page, rowShiftLauncher(page, rowIndex));
    await fillRosterShiftDialogDefaults(page);
    const staffSelect = page.locator('#roster-shift-staff-id');
    await staffSelect.selectOption(staffId);
    const expectedStaffLabel = (await staffSelect.locator('option:checked').textContent())?.trim() ?? '';
    await saveRosterShiftDialog(page);
    await expect(rowShiftLauncher(page, rowIndex).locator('.slot-staff-cell')).toContainText(expectedStaffLabel, {
        timeout: E2E_TIMEOUT.liveUpdate,
    });
}

async function normalizeRosterForDuplicateConflict(actorPage: Page) {
    const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';

    await ensureTwoEditableRosterRows(actorPage);
    const alternateStaffId = (await staffOptionsForRow(actorPage, 1)).find((value) => value !== alphaCrewStaffId && value !== 'open');
    expect(alternateStaffId).toBeTruthy();

    await assignStaffToRow(actorPage, 0, alphaCrewStaffId);
    await assignStaffToRow(actorPage, 1, alternateStaffId!);
    await expect(duplicateConflictCells(actorPage)).toHaveCount(0);
}

function duplicateConflictCells(page: Page) {
    return page.locator('.slot-staff-cell.conflict-critical');
}

test.describe('Roster duplicate conflicts', () => {
    test.describe.configure({ retries: 0 });

    test('actor duplicate conflict highlighting refreshes immediately after staff assignment', async ({ page }) => {
        await loginAndOpenRoster(page);
        await normalizeRosterForDuplicateConflict(page);

        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        const initialConflictCount = await duplicateConflictCells(page).count();

        await assignStaffToRow(page, 1, alphaCrewStaffId);
        await expect
            .poll(async () => duplicateConflictCells(page).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialConflictCount);
    });

    test('keeps disabled warning colours hidden across hover highlights while retaining tooltips', async ({ page }) => {
        await loginAndOpenRoster(page);
        await normalizeRosterForDuplicateConflict(page);
        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        await assignStaffToRow(page, 1, alphaCrewStaffId);

        const conflictCell = duplicateConflictCells(page).first();
        await expect(conflictCell).toHaveAttribute('title', /.+/);
        await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-warnings', 'hidden');
        const hiddenBackground = await conflictCell.evaluate((cell) => getComputedStyle(cell).backgroundImage);

        await conflictCell.hover();
        await expect.poll(async () => conflictCell.evaluate((cell) => getComputedStyle(cell).backgroundImage)).toBe(hiddenBackground);

        const launcher = conflictCell.locator('xpath=ancestor::*[@data-roster-shift-launcher="true"][1]');
        const staffKey = await launcher.getAttribute(rosterStaffHighlightMemberDomAttr);
        expect(staffKey).toBeTruthy();
        const staffRow = page.locator(`[${rosterStaffPanelSortRowDomAttr}][${rosterStaffHighlightSourceDomAttr}="${staffKey}"]`).first();
        await staffRow.hover();
        await expect.poll(async () => conflictCell.evaluate((cell) => getComputedStyle(cell).backgroundImage)).toBe(hiddenBackground);

        await launcher.hover();
        await expect.poll(async () => conflictCell.evaluate((cell) => getComputedStyle(cell).backgroundImage)).toBe(hiddenBackground);
    });

    test('actor and viewer both keep duplicate conflict highlighting without breaking the roster grid', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage, multiviewDuplicateConflictWeekOffset);
        await normalizeRosterForDuplicateConflict(actorPage);

        await loginAndOpenRoster(viewerPage, multiviewDuplicateConflictWeekOffset);
        await expect
            .poll(async () => editableRosterRows(viewerPage).count())
            .toBeGreaterThanOrEqual(2);
        const initialActorConflictCount = await duplicateConflictCells(actorPage).count();
        const initialViewerConflictCount = await duplicateConflictCells(viewerPage).count();

        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        await assignStaffToRow(actorPage, 1, alphaCrewStaffId);
        await expect
            .poll(async () => duplicateConflictCells(actorPage).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialActorConflictCount);
        await viewerPage.reload();
        await expect(viewerPage.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.navigation });
        await expect
            .poll(async () => duplicateConflictCells(viewerPage).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialViewerConflictCount);

        const viewerGridState = await viewerPage.locator('.roster-grid').evaluate((grid) => {
            const bodyRows = Array.from(grid.querySelectorAll('[data-roster-row]'));
            const outsideRows = Array.from(document.querySelectorAll('[data-roster-row]')).filter(
                (row) => !row.closest('.roster-grid-day-section'),
            );
            const visualCellCount = (row: Element | undefined) =>
                row?.querySelector('[data-roster-shift-launcher="true"]')?.querySelectorAll('.roster-shift-unit-cell, .roster-shift-card-field').length ?? 0;
            return {
                bodyRowCount: bodyRows.length,
                outsideRowCount: outsideRows.length,
                editableBodyRowCount: bodyRows.filter((row) => row.querySelector('[data-roster-shift-launcher="true"]')).length,
                firstRowCellCount: visualCellCount(bodyRows[0]),
                secondRowCellCount: visualCellCount(bodyRows[1]),
                launcherCount: grid.querySelectorAll('[data-roster-shift-launcher="true"]').length,
            };
        });

        expect(viewerGridState.outsideRowCount).toBe(0);
        expect(viewerGridState.editableBodyRowCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.launcherCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.bodyRowCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.firstRowCellCount).toBeGreaterThanOrEqual(3);
        expect(viewerGridState.secondRowCellCount).toBeGreaterThanOrEqual(3);

        await actorContext.close();
        await viewerContext.close();
    });
});
