import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { addRowToRosterDay, firstEditableRosterDaySection, openRoster } from './test-helpers';

async function loginAndOpenRoster(page) {
    await openRoster(page);
}

function editableRosterRows(page) {
    return page.locator('tr[data-roster-row]').filter({ has: page.locator('select[name="staffId"]') });
}

async function ensureTwoEditableRosterRows(page) {
    const rows = editableRosterRows(page);
    const initialCount = await rows.count();
    if (initialCount >= 2) {
        return;
    }

    await addRowToRosterDay(firstEditableRosterDaySection(page));
    await expect(rows).toHaveCount(initialCount + 1);
    await expect(rows).toHaveCount(2);
}

async function assignStaffToRow(page, rowIndex, staffId) {
    const row = editableRosterRows(page).nth(rowIndex);
    const select = row.locator('select[name="staffId"]').first();
    const updateUrl = await select.getAttribute('hx-post');
    if (!updateUrl) {
        throw new Error('Expected roster staff select to have an hx-post update URL');
    }
    await Promise.all([
        page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().endsWith(updateUrl),
        ),
        select.selectOption(staffId),
    ]);
    await expect(select).toHaveValue(staffId);
}

async function blurActiveRosterInput(page) {
    await page.evaluate(() => {
        const activeElement = document.activeElement;
        if (activeElement instanceof HTMLElement) {
            activeElement.blur();
        }
    });
}

async function normalizeRosterForDuplicateConflict(actorPage) {
    const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';

    await ensureTwoEditableRosterRows(actorPage);
    await assignStaffToRow(actorPage, 0, '');
    await blurActiveRosterInput(actorPage);
    await assignStaffToRow(actorPage, 1, '');
    await blurActiveRosterInput(actorPage);
    await expect(duplicateConflictCells(actorPage)).toHaveCount(0);
    await assignStaffToRow(actorPage, 0, alphaCrewStaffId);
    await blurActiveRosterInput(actorPage);
    await expect(duplicateConflictCells(actorPage)).toHaveCount(0);
}

function duplicateConflictCells(page) {
    return page.locator('.slot-staff-cell.conflict-critical');
}

test.describe('Roster duplicate conflicts', () => {
    test.describe.configure({ retries: 0 });

    test('actor duplicate conflict highlighting refreshes immediately after staff assignment', async ({ page }) => {
        await loginAndOpenRoster(page);
        await normalizeRosterForDuplicateConflict(page);

        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        const duplicateTargetRow = editableRosterRows(page).nth(1);
        const duplicateTargetSelect = duplicateTargetRow.locator('select[name="staffId"]').first();
        const initialConflictCount = await duplicateConflictCells(page).count();

        await duplicateTargetSelect.selectOption(alphaCrewStaffId);
        await expect(duplicateTargetSelect).toHaveValue(alphaCrewStaffId);
        await blurActiveRosterInput(page);
        await expect
            .poll(async () => duplicateConflictCells(page).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialConflictCount);
    });

    test('actor and viewer both keep duplicate conflict highlighting without breaking the roster grid', async ({ browser }) => {
        const actorContext = await browser.newContext();
        const viewerContext = await browser.newContext();
        const actorPage = await actorContext.newPage();
        const viewerPage = await viewerContext.newPage();

        await loginAndOpenRoster(actorPage);
        await normalizeRosterForDuplicateConflict(actorPage);

        await loginAndOpenRoster(viewerPage);
        await expect(editableRosterRows(viewerPage)).toHaveCount(2);
        const initialActorConflictCount = await duplicateConflictCells(actorPage).count();
        const initialViewerConflictCount = await duplicateConflictCells(viewerPage).count();

        const alphaCrewStaffId = 'a1000000-0000-0000-0000-000000000031';
        await assignStaffToRow(actorPage, 1, alphaCrewStaffId);
        await blurActiveRosterInput(actorPage);
        await expect
            .poll(async () => duplicateConflictCells(actorPage).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialActorConflictCount);
        await expect
            .poll(async () => duplicateConflictCells(viewerPage).count(), { timeout: E2E_TIMEOUT.liveUpdate })
            .toBeGreaterThan(initialViewerConflictCount);

        const viewerGridState = await viewerPage.locator('table.roster-grid').evaluate((table) => {
            const bodyRows = Array.from(table.querySelectorAll('tbody > tr[data-roster-row]'));
            const outsideRows = Array.from(document.querySelectorAll('tr[data-roster-row]')).filter(
                (row) => !row.closest('tbody'),
            );
            return {
                bodyRowCount: bodyRows.length,
                outsideRowCount: outsideRows.length,
                editableBodyRowCount: bodyRows.filter((row) => row.querySelector('select[name="staffId"]')).length,
                firstRowCellCount: bodyRows[0]?.children.length ?? 0,
                secondRowCellCount: bodyRows[1]?.children.length ?? 0,
                selectCount: table.querySelectorAll('select[name="staffId"]').length,
            };
        });

        expect(viewerGridState.outsideRowCount).toBe(0);
        expect(viewerGridState.editableBodyRowCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.selectCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.bodyRowCount).toBeGreaterThanOrEqual(2);
        expect(viewerGridState.firstRowCellCount).toBeGreaterThanOrEqual(3);
        expect(viewerGridState.secondRowCellCount).toBeGreaterThanOrEqual(3);

        await actorContext.close();
        await viewerContext.close();
    });
});
